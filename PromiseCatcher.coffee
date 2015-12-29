class PromiseCatcher
    Promise = require('promise')
    Path = require('path')
    Fs = require('fs')

    thisInstance = null
    
    liveCacheItems = 
        metaData: []
        ids: []
        count: 0

    candidateQueue =
        requestCount : []
        ids: []

    debugMode = true
    cachePath = ''
    maxCacheItems = 1024
    clearCacheSizeFraction = 4
    candidateQueueLength = 20
    candidateRequestThreshold = 2
    cacheTimeToLive = 0
    
    @Instance: (options) ->
        thisInstance ?= new instancePrivateClass(options)
    
    class instancePrivateClass
        constructor: (options) ->
            options.cachePath?= ''
            options.ttl ?= 0
            options.maxCacheItems?=1024
            options.clearCacheSizeFraction?=4
            options.candidateQueueLength?=20
            options.candidateRequestThreshold?=2
            options.debug?=false
            
            debugMode = options.debug
            cachePath = options.cachePath + 'promises' + Path.sep
            maxCacheItems = options.maxCacheItems
            clearCacheSizeFraction = options.clearCacheSizeFraction
            candidateQueueLength = options.candidateQueueLength
            candidateRequestThreshold = options.candidateRequestThreshold
            options.ttl
            
            # create an empty set of queues
            index = 0
            while index++ < candidateQueueLength
                candidateQueue.ids.push('')
                candidateQueue.requestCount.push(0)
            
            # delete any existing cache items on disk, or make a new cache directory if none exists
            if  Fs.existsSync(cachePath)
                Fs.readdirSync(cachePath).forEach (file,index) ->
                    curPath = cachePath + file
                    Fs.unlinkSync curPath
            else
                Fs.mkdir cachePath
                
        
        GetCache: ( id, promisesToCache ) ->
            # make sure to get rid of any directory path delimiters from the cache ID
            id = '' + id.replace(/[\\\/]/g,'_')
            promises = null

            # does this id exists in the cache yet?
            if (liveCacheItems.ids[id] != undefined)
                indexMetaData =  liveCacheItems.ids[id];
                item = liveCacheItems.metaData[indexMetaData];
                
                # the id in the metadata should match the id of the cache item. If not it is corrupt
                # this *might* happen during a clearCache and simultaneously many cache set requests come in.
                # it would be pretty rare for that to happen.
                if item.id == id
                    promises = getCache id, promisesToCache
                else
                    if debugMode
                        console.log('corrupt ' + id)
                        console.log(item)
                        console.log(liveCacheItems.metaData[indexMetaData+1])
                        console.log(liveCacheItems.metaData[indexMetaData-1])
                    
                    promises = sendBackPromises promisesToCache
            else
                promises = sendBackPromises promisesToCache                 
         
            promises
            
        SetCache: ( id, data, ttl ) ->
            # make sure to get rid of any directory path delimiters from the cache ID
            id = '' + id.replace(/[\\\/]/g,'_')
            ttl?=cacheTimeToLive
            setCache id, data, ttl
            
    #Private methods

    getCache = ( id, promisesToCache ) ->
        returnPromises = null
        
        # are we dealing with a list of Promises or a single function that returns a Promise
        # regardless, if the item is cached, return a Promise that will read the cached Promise from disk
        if promisesToCache.length > 0
            returnPromises = []
            dataIndex = -1
            while (++dataIndex < promisesToCache.length)
                returnPromises.push new Promise (fulfill, reject) ->
                    thisIndex = dataIndex
                    Fs.readFile "#{cachePath}#{id}", (err, data) ->
                        if err?
                            console.log(err)
                            fulfill(promisesToCache)
                        else
                            indexMetaData =  liveCacheItems.ids[id];
                            liveCacheItems.metaData[indexMetaData].lastUsed = Date.now()
                            cachedData = JSON.parse(data)
                            cachedData[thisIndex].IsFromPromiseCatcher = true
                            fulfill(cachedData[thisIndex])
        else
            returnPromises = new Promise (fulfill, reject) ->
                Fs.readFile "#{cachePath}#{id}", (err, data) ->
                    if err?
                        console.log(err)
                        fulfill(promisesToCache)
                    else
                        indexMetaData =  liveCacheItems.ids[id];
                        liveCacheItems.metaData[indexMetaData].lastUsed = Date.now()
                        cachedData = JSON.parse(data)
                        cachedData.IsFromPromiseCatcher = true
                        fulfill(cachedData)        
        returnPromises
        

    setCache = ( id, data, ttl ) ->
        # see if this Promise data is "worthy" of being cached yet - and save to disk if so
        if isCandidate candidateQueue, id
            Fs.writeFile "#{cachePath}#{id}", JSON.stringify(data), (err, data) ->
                if err?
                    console.log(err)
                else
                    # have we exceeded the maximum cache size yet? If so clear it and start fresh
                    if  liveCacheItems.count >= maxCacheItems then cleanCache maxCacheItems
                    
                    # save the metadata for this item
                    if liveCacheItems.ids[id] == undefined
                        indexMetaData = liveCacheItems.metaData.push( {id: id, lastUsed: Date.now()} )
                        liveCacheItems.ids[id] = indexMetaData-1
                        ++liveCacheItems.count
                    else
                        liveCacheItems.metaData[ liveCacheItems.ids[id] ].lastUsed = Date.now()
                    
                    if debugMode
                        console.log(liveCacheItems)

                        
    cleanCache = ( ) ->
        # the idea here is to sort the items so that the last used ones are at the front of the list
        # and the truncate the list so it is a fraction (clearCacheSizeFraction) of its original size 
        # and start building the list again
        liveCacheItems.metaData.sort ( a,b ) ->
            b.lastUsed - a.lastUsed
            
        liveCacheItems.metaData.length = Math.floor(maxCacheItems/clearCacheSizeFraction)
        # delete the entire list of cached items and re-build based on the truncated metadata list
        liveCacheItems.ids = []
        
        liveCacheItems.count = 0
        indexMetaData = 0
        while indexMetaData < liveCacheItems.metaData.length
            liveCacheItems.ids[liveCacheItems.metaData[indexMetaData].id] = indexMetaData++
            
        liveCacheItems.count = indexMetaData

    isCandidate = ( candidateQueue, id ) ->
        # this uses what I call the "Nightclub Bouncer" algorithm
        # a queue of candidates are present, and every request for a candidate increases their hit 
        # counter if the counter is above the candidateRequestThreshold you are deemed a "hottie" 
        # and you are "approved" (we return true) and you get into the club
        # every time a new id comes in the queue shift by one and the id at the head of the queue
        # drops out, and the new id is added at the end of the queue ("back of the line, you!")
        # if the caching list is cleared by clearCache and an id drops out but is still in the
        # candidateQueue, the next request for that id will immediately be cached as if
        # "the hottie left the club but is a VIP now" so they get back in right away
        
        candidateIndex = candidateQueue.ids.indexOf(id)
        if candidateIndex != -1
            candidateRequestCount = ++candidateQueue.requestCount[candidateIndex]
        else
            candidateIndex = candidateQueue.ids.push(id)
            candidateRequestCount = 1
            candidateIndex = candidateQueue.requestCount.push(candidateRequestCount)
            candidateQueue.ids.shift()
            candidateQueue.requestCount.shift()
        
        if debugMode
            console.log(candidateQueue)

        candidateRequestCount > candidateRequestThreshold
        
    sendBackPromises = ( promisesToCache ) ->
        promisesToReturn = null
        
        if promisesToCache.length > 0
            promisesToReturn = []
            promiseIndex = 0
            
            while promiseIndex < promisesToCache.length
                promisesToReturn.push promisesToCache[promiseIndex]
                promiseIndex++
        else
            promisesToReturn = promisesToCache
        
        promisesToReturn
                    
module.exports = PromiseCatcher