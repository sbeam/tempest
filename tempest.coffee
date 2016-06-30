request = require('request-promise')
liner = require('n-readlines')
q = require 'q'

# Tempest.
# A log-replay script that attempts to excercise a fork/staging app in the same
# way as live production traffic, with the exact same requests and timing
# distribution (assuming GET requests). Parses a raw heroku log dump, using the
# lines from the router, to re-construct and request at the same time offset.
#
#   * Prints a simple '^' for an outgoing request, and a '.' for a received request.
#
#   * Reports on any results where the status code differs from the one
#     received in production, and offers you a handy `curl` command you can use
#     to replicate the request.
#
#   * When complete, reports on count, total time and the total difference in
#     response times for each status code received.
#
# Can replay any log file size, have not tried up to 4000 requests or so.
#
# TODO:
#   * better output with colorization and all that jazz
#   * better final report output with a table
#
#
# HOW TO USE:
#
# 1) grab sample of production logs via 'heroku logs -t' into a file, eg:
#    heroku logs -t -a my-cool-app > bigfatlogfile.log
#
# 2) invoke per usage() below:

usage = ->
  console.log "Usage: coffee tempest.coffee http://example-host.com/ bigfatlogfile.log"
  process.exit()


specialCategories = {
  www: 'reviewed'
  projectors: 'videoprojectors'
}

host = process.argv[2] || usage()
logfile = process.argv[3] || usage()


fetches = []

lines = new liner(logfile)


now = new Date
first_time = null

responseHandler = ->
  [origStatus, request_start, origMillis] = arguments
  (response)->
    process.stdout.write('.')
    elapsed = (new Date).getTime() - request_start
    status = response.statusCode+""

    if !status
      console.error("#{response.name} at #{response.options.url}")
    else
      if status != "200"
        response = response.response # lol
      if origStatus != status and not (status == "200" && origStatus == "304")
        cat = response.request.headers['X-Reviewed-Category']
        console.log("\nstatus #{status} (was #{origStatus}) in #{elapsed}ms: `curl -I -H X-Reviewed-Category:#{cat} #{response.request.uri.href}`")

    { bytes: response.body?.length, time: elapsed, status: response.statusCode, diff: elapsed - origMillis }

queueRequest = (offset, path, department, origStatus, origMillis)->
  request_options = {
    url: host + path
    followRedirect: false
    resolveWithFullResponse: true
    headers: {
      "X-Reviewed-Category": specialCategories[department] || department
    }
  }

  origStatus = origStatus
  #console.log "path=#{path} department=#{department} delay=#{offset}"

  fetches.push q.delay(offset).then ->
    process.stdout.write('^')
    request_start = (new Date).getTime()
    request(request_options)
      .then(responseHandler(origStatus, request_start, origMillis))
      .catch(responseHandler(origStatus, request_start, origMillis))

while line = lines.next()
  line = line.toString('ascii')
  parts = line.split(' ')
  # filter to lines that describe GET requests via the router
  continue unless (parts.length > 11 and parts[1] == 'heroku[router]:' and parts[3] == 'method=GET')

  unless first_time
    first_time = (new Date(Date.parse(parts[0]))).getTime()

  time = (new Date(Date.parse(parts[0]))).getTime()
  path = parts[4].replace(/^path=\"([^\"]+)\"/, '$1')
  department = parts[5].replace(/^host=([^.]+).reviewed.com/, '$1')
  origStatus = parts[11].replace(/^status=([\w\d]+)/, '$1')
  origMillis = parseInt(parts[10].split('=')[1])

  offset = time - first_time

  queueRequest(offset, path, department, origStatus, origMillis)

console.log "#{fetches.length} requests queued up!"

q.allSettled(fetches).then (results)->
  console.log "\n--\n%d requests complete.", results.length
  tally = {}
  results.forEach (data)->
    status = data.value?.status || 'WTF'
    (tally[status] ||= {bytes: 0, time: 0, count: 0, diff: 0})['bytes'] += data.value?.bytes || 0
    tally[status]['time'] += data.value?.time || 0
    tally[status]['diff'] += data.value?.diff || 0
    tally[status]['count']++

  for own code, values of tally
    console.log "%s: %d requests, %d bytes, total %dsec, diff=%dms", code, values.count, values.bytes, values.time/1000, values.diff
