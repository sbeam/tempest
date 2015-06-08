request = require('request-promise')
logger = require('winston')
liner = require('n-readlines')
q = require 'q'

now = new Date

first_time = null

host = 'hydra-staging.herokuapp.com'
port = '80'

totals = {}
fetches = []

lines = new liner('607.log')


queueRequest = (offset, path, department)->
  request_options = {
    url: "http://#{host}:#{port}#{path}"
    headers: { "X-Reviewed-Category": department }
    resolveWithFullResponse: true
  }

  console.log("path=#{path} delay=#{offset}")

  fetches.push q.delay(offset).then ->
    request_start = (new Date).getTime()

    request(request_options).then( (response)->
      elapsed = (new Date).getTime() - request_start
      logger.info("status #{response.statusCode} in #{elapsed}ms at (#{department})#{request_options.url}")
      { bytes: response.body?.length, time: elapsed, status: response.statusCode }
    ).catch (response)->
      elapsed = (new Date).getTime() - request_start
      logger.warn("status #{response.statusCode} in #{elapsed}ms at (#{department})#{request_options.url}")
      { bytes: response.body?.length, time: elapsed, status: response.statusCode }





while line = lines.next()
  line = line.toString('ascii')
  parts = line.split(' ')
  continue unless parts.length > 5

  unless first_time
    first_time = (new Date(Date.parse(parts[0]))).getTime()

  time = (new Date(Date.parse(parts[0]))).getTime()
  path = parts[4].replace(/^path=\"([^\"]+)\"/, '$1')
  department = parts[5].replace(/^host=([^.]+).reviewed.com/, '$1')

  offset = time - first_time

  queueRequest(offset, path, department)



console.log "done with lines! #{fetches.length}"

q.allSettled(fetches).then (results)->
  console.log "#{results.length} requests complete."
  tally = {}
  results.forEach (data)->
    (tally[data.value.status] ||= {bytes: 0, time: 0, count: 0})['bytes'] += data.value.bytes
    tally[data.value.status]['time'] += data.value.time || 0
    tally[data.value.status]['count']++
  for own code, values of tally
    console.log("#{code}: #{values.count} requests, #{values.bytes} bytes, #{values.time/1000}sec")


