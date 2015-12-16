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
            options.candidateQueueLength?=20
            options.candidateRequestThreshold?=2
            options.debug?=false
            
            debugMode = options.debug
            cachePath = options.cachePath + 'promises' + Path.sep
            maxCacheItems = options.maxCacheItems
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
            id = '' + id.replace(/[\\\/]/g,'_')
            promises = null

            if (liveCacheItems.ids[id] != undefined)
                indexMetaData =  liveCacheItems.ids[id];
                item = liveCacheItems.metaData[indexMetaData];
                
                if item.id == id
                    promises = getCache id, promisesToCache
                else
                    promises = sendBackPromises promisesToCache
            else
                promises = sendBackPromises promisesToCache                 
         
            promises
            
        SetCache: ( id, data, ttl ) ->
            id = '' + id.replace(/[\\\/]/g,'_')
            ttl?=cacheTimeToLive
            setCache id, data, ttl
            
    #Private methods

    getCache = ( id, promisesToCache ) ->
        returnPromises = null
        
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
        if isCandidate candidateQueue, id 
            Fs.writeFile "#{cachePath}#{id}", JSON.stringify(data), (err, data) ->
                if err?
                    console.log(err)
                else
                    if  liveCacheItems.count >= maxCacheItems then cleanCache maxCacheItems
                    liveCacheItems.ids[id] = liveCacheItems.metaData.push( {id: id, lastUsed: Date.now()} )
                    ++liveCacheItems.count
                    
                    if debugMode
                        console.log(liveCacheItems)

                        
    cleanCache = ( ) ->
        liveCacheItems.metaData.sort ( a,b ) ->
            b.lastUsed - a.lastUsed
        liveCacheItems.metaData.length = Math.floor(maxCacheItems/4)
        liveCacheItems.ids = []
        liveCacheItems.count = 0
        indexMetaData = 0
        while indexMetaData < liveCacheItems.metaData.length
            liveCacheItems.ids[liveCacheItems.metaData[indexMetaData].id] = indexMetaData++
            
        liveCacheItems.count = indexMetaData

    isCandidate = ( candidateQueue, id ) ->
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