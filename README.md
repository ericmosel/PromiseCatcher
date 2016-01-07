Promise Catcher
=========

A disk-based caching module for caching time-expensive Promises in NodeJS

## Installation

  npm install promise-catcher --save

## Usage

    //This is implemented as a singleton, so we just do the below *once* ... and apps.js is a good place as when the singleton is first called, it will delete any old cache files in the cachePath directory. You probably want this to happen when NodeJS starts up, rather than later.

    require('promise-catcher').Instance( 
                                            {
                                                cachePath: 'path/to/cache/files/here/', 
                                                maxCacheItems: 2048, // total number of items to cache
                                                candidateQueueLength: 200, // this dermines candidate promises to cache - I'll explain later just use this value ha ha
                                                candidateRequestThreshold: 3, // this says you have to request the cached Pronise three times in 200 requests and then it will be cached. Make it 1 if you want it to cache right away
                                                debug: false
                                            }
    );


    // from this point, later in your code, if you are using just a single, simple Promise, you can do something like
    // first define your Promise function.
    function doSomethingThatTakesTime(data){
      return new Promise(function (fulfill, reject){
        somethingCostlyHappensHere(data, function (err, res){
          if (err) reject(err);
          else fulfill(res);
        });
      });
    }

   // somewhere else in your code in a file in another galaxy far, far away ...
   // now call and cache it using Promise Catcher singleton - use it just like a Promise ! 
   // in this example we cache the Promise with a cache name 'aCachedPromise'.
   var PromiseCatcher = require('promise-catcher').Instance( );
   PromiseCatcher.GetCache('aCachedPromise', doSomethingThatTakesTime(data) ).done( function (promiseInfo){
        // do something with the Promise data in here
        // first, see if we this has already been cached, and if not let's request a save to cache
        // we set the candidateRequestThreshold to three so the below would have to happen 3 times before promiseInfo is actually saved to 
        // at 3 requests to cache, in this example, the Promise is "deemed worthy" of being cached.
        if (! promiseInfo.IsFromPromiseCatcher){
            PromiseCatcher.SetCache( 'aCachedPromise', promiseInfo );
        }
        
        // now you'd do whatever you would usually do with your Promise data -
        // promiseInfo ... yada yada yada ....
   });
   
    
## Release History

* 1.0.0 Initial release