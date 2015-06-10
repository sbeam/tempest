request = require('request-promise')
liner = require('n-readlines')
q = require 'q'

usage = ->
  console.log "Usage: coffee tempest.coffee http://example-host.com/ bigfatlogfile.log"
  process.exit()

host = process.argv[2] || usage()
logfile = process.argv[3] || usage()


fetches = []

lines = new liner(logfile)


now = new Date
first_time = null

responseHandler = ->
  [origStatus, request_start] = arguments
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
    { bytes: response.body?.length, time: elapsed, status: response.statusCode }

queueRequest = (offset, path, department, origStatus)->
  request_options = {
    url: host + path
    followRedirect: false
    resolveWithFullResponse: true
    headers: {
      "X-Reviewed-Category": if (department == 'www') then 'reviewed' else department
    }
  }

  origStatus = origStatus
  console.log "path=#{path} department=#{department} delay=#{offset}"

  fetches.push q.delay(offset).then ->
    process.stdout.write('^')
    request_start = (new Date).getTime()
    request(request_options)
      .then(responseHandler(origStatus, request_start))
      .catch(responseHandler(origStatus, request_start))

while line = lines.next()
  line = line.toString('ascii')
  parts = line.split(' ')
  continue unless parts.length > 11

  unless first_time
    first_time = (new Date(Date.parse(parts[0]))).getTime()

  time = (new Date(Date.parse(parts[0]))).getTime()
  path = parts[4].replace(/^path=\"([^\"]+)\"/, '$1')
  department = parts[5].replace(/^host=([^.]+).reviewed.com/, '$1')
  origStatus = parts[11].replace(/^status=([\w\d]+)/, '$1')

  offset = time - first_time

  queueRequest(offset, path, department, origStatus)

console.log "#{fetches.length} requests queued up!"

q.allSettled(fetches).then (results)->
  console.log "\n--\n%d requests complete.", results.length
  tally = {}
  results.forEach (data)->
    status = data.value?.status || 'WTF'
    (tally[status] ||= {bytes: 0, time: 0, count: 0})['bytes'] += data.value?.bytes || 0
    tally[status]['time'] += data.value?.time || 0
    tally[status]['count']++
  for own code, values of tally
    console.log "%s: %d requests, %d bytes, %dsec", code, values.count, values.bytes, values.time/1000
