//
//  TwoLevelCache.swift
//  Pods-TwoLevelCache_Example
//
//  Created by 澤良弘 on 2017/10/06.
//

import Foundation

public enum TwoLevelCacheLoadStatus: Int {
    case downloader = 3
    case error = -1
    case file = 2
    case memory = 1
}

open class TwoLevelCache<T: NSObject>: NSObject {
    public var downloader: ((String, @escaping (Data?) -> Void) -> Void)!
    public let name: String
    public var objectDecoder: ((Data) -> T?)!
    public var objectEncoder: ((T) -> Data?)!
    let fileCacheDirectory: URL
    let fileManager = FileManager()
    let memoryCache = NSCache<NSString, T>()
    let queue = DispatchQueue(label: "com.nzigen.TwoLevelCache.queue", attributes: .concurrent)

    public init(_ name: String) throws {
        self.name = name
        self.memoryCache.name = name
        
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fileCacheDirectory = url.appendingPathComponent("com.nzigen.TwoLevelCache/\(name)")
        
        try fileManager.createDirectory(at: fileCacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func loadObjectForKey(_ key: String, callback: @escaping (T?, TwoLevelCacheLoadStatus) -> Void) {
        queue.async {
            let keyString = key as NSString
            if let object = self.memoryCache.object(forKey: keyString) {
                callback(object, .memory)
                return
            }
            let url = self.encodeFilePath(key)
            let data = try? Data(contentsOf: url)
            if let data = data {
                if let object = self.objectDecoder(data) {
                    self.queue.async {
                        self.memoryCache.setObject(object, forKey: keyString)
                    }
                    callback(object, .file)
                    return
                }
            }
            self.downloader(key, { (_ data: Data?) in
                if let data = data {
                    if let object = self.objectDecoder(data) {
                        self.queue.async {
                            self.saveObject(object, forMemoryCacheKey: key)
                            self.saveData(data, forFileCacheKey: key)
                        }
                        callback(object, .downloader)
                        return
                    }
                }
                callback(nil, .error)
            })
        }
    }
    
    public func removeAllObjects() {
        self.memoryCache.removeAllObjects()
        let urls = try? self.fileManager.contentsOfDirectory(at: self.fileCacheDirectory, includingPropertiesForKeys: nil, options: [])
        urls?.forEach({ (url) in
            try? self.fileManager.removeItem(at: url)
        })
    }
    
    public func removeAllObjects(callback: (() -> Void)?) {
        queue.async {
            self.removeAllObjects()
            callback?()
        }
    }
    
    public func removeObjectForKey(_ key: String) {
        self.memoryCache.removeObject(forKey: key as NSString)
        let url = self.encodeFilePath(key)
        try? self.fileManager.removeItem(at: url)
    }
    
    public func saveData(_ data: Data, forFileCacheKey key: String) {
        let url = self.encodeFilePath(key)
        try? data.write(to: url)
    }
    
    public func saveData(_ data: Data, forMemoryCacheKey key: String) {
        if let object = objectDecoder(data) {
            memoryCache.setObject(object, forKey: key as NSString)
        } else {
            memoryCache.removeObject(forKey: key as NSString)
        }
    }
    
    public func saveData(_ data: Data, forKey key: String) {
        saveData(data, forMemoryCacheKey: key)
        saveData(data, forFileCacheKey: key)
    }
    
    public func saveObject(_ object: T, forFileCacheKey key: String) {
        let url = self.encodeFilePath(key)
        if let data = self.objectEncoder(object) {
            try? data.write(to: url)
        } else {
            try? self.fileManager.removeItem(at: url)
        }
    }
    
    public func saveObject(_ object: T, forMemoryCacheKey key: String) {
        memoryCache.setObject(object, forKey: key as NSString)
    }
    
    public func saveObject(_ object: T, forKey key: String) {
        saveObject(object, forMemoryCacheKey: key)
        saveObject(object, forFileCacheKey: key)
    }
    
    private func encodeFilePath(_ path: String) -> URL {
        let data: Data = path.data(using: .utf8)!
        let url = fileCacheDirectory
            .appendingPathComponent(data.base64EncodedString(options: [Data.Base64EncodingOptions.lineLength64Characters, Data.Base64EncodingOptions.endLineWithLineFeed]))
            .appendingPathExtension("cache")
        return url
    }
}
