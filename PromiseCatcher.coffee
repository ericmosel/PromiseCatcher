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
    
    @Instance: (options) ->
        thisInstance ?= new instancePrivateClass(options)
    
    class instancePrivateClass
        constructor: (options) ->
            options.cachePath?= ''
            options.ttl ?= 1024
            options.maxCacheItems?=256
            options.candidateQueueLength?=20
            options.candidateRequestThreshold?=2
            options.debug?=false
            
            debugMode = options.debug
            cachePath = options.cachePath + 'promises' + Path.sep
            maxCacheItems = options.maxCacheItems
            candidateQueueLength = options.candidateQueueLength
            candidateRequestThreshold = options.candidateRequestThreshold 
            
            index = 0
            while index++ < candidateQueueLength
                candidateQueue.ids.push('')
                candidateQueue.requestCount.push(0)
            
            cachePath = options.cachePath + 'promises' + Path.sep
            maxCacheItems = options.maxCacheItems
            
            if  Fs.existsSync(cachePath)
                Fs.readdirSync(cachePath).forEach (file,index) ->
                    curPath = cachePath + file
                    Fs.unlinkSync curPath
            else
                Fs.mkdir cachePath
                
        
        GetCache: ( id, promisesToCache ) ->
            promises = []
            if (liveCacheItems.ids[id] != undefined)
                indexMetaData =  liveCacheItems.ids[id];
                item = liveCacheItems.metaData[indexMetaData];
                if ''+item.id == ''+id
                    promises = getCache id, promisesToCache
                else
                    promiseIndex = 0
                    while promiseIndex < promisesToCache.length
                        promises.push promisesToCache[promiseIndex]
                        promiseIndex++                

            else
                promiseIndex = 0
                while promiseIndex < promisesToCache.length
                    promises.push promisesToCache[promiseIndex]
                    promiseIndex++
                    
            promises
            
        SetCache: ( id, data ) ->
            setCache id, data
            
    #Private methods

    getCache = ( id, promisesToCache ) ->
        returnPromises = []
        dataIndex = -1
        while (++dataIndex < promisesToCache.length)
            returnPromises.push new Promise (fulfill, reject) ->
                Fs.readFile "#{cachePath}#{id}_#{dataIndex}", (err, data) ->
                    if err?
                        console.log(err)
                        fulfill([])
                    else
                        indexMetaData =  liveCacheItems.ids[id];
                        liveCacheItems.metaData[indexMetaData].lastUsed = Date.now()
                        cachedData = JSON.parse(data)
                        cachedData.IsFromPromiseCatcher = true
                        fulfill(cachedData)
        
        returnPromises
        

    setCache = ( id, data ) ->
        if isCandidate candidateQueue, id 
            Fs.writeFile "#{cachePath}#{id}_0", JSON.stringify(data[0]), (err, data) ->
                if err?
                    console.log(err)
                else
                    if  liveCacheItems.count >= maxCacheItems then cleanCache maxCacheItems
                    liveCacheItems.ids[id] = liveCacheItems.metaData.length
                    ++liveCacheItems.count
                    liveCacheItems.metaData.push( {id: id, lastUsed: Date.now()} )
                    if debugMode
                        console.log(liveCacheItems)

            dataIndex = 0
            while (++dataIndex < data.length)                        
                Fs.writeFile "#{cachePath}#{id}_#{dataIndex}", JSON.stringify(data[dataIndex]), (err, data) ->
                    if err?
                        console.log(err)

                        
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
        
        
module.exports = PromiseCatcher