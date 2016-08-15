//
//  RequestTask.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/12.
//  Copyright © 2016年 ymh. All rights reserved.
//  做下载、持久化的

import Foundation

public class RequestTask: NSObject {
    
    var tempPath: String = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true).last! + "/temp.mp4"     //  缓冲文件路径 - 非持久化文件路径 - 当前逻辑下，有且只有一个缓冲文件
    
    public var url: NSURL?
    public var offset: Int = 0                 //  请求位置（从哪开始）
    public var taskArr = [NSURLConnection]()   //  NSURLConnection的数组
    public var downLoadingOffset: Int = 0   //  已下载数据长度
    public var videoLength: Int = 0         //  视频总长度
    public var isFinishLoad: Bool = false   //  是否下载完成
    public var mimeType: String?            //  传输文件格式
    
    //  代理方法们
    public var recieveVideoInfoHandler: ((task: RequestTask, videoLength: Int, mimeType: String)->())?  //  获取到了信息
    public var receiveVideoDataHandler: ((task: RequestTask)->())?  //  获取到了数据
    public var receiveVideoFinishHanlder: ((task: RequestTask)->())?    //  获取信息结束
    public var receiveVideoFailHandler: ((task: RequestTask, error: NSError)->())?
    
    private var connection: NSURLConnection?    //  下载连接
    private var fileHandle: NSFileHandle?       //  文件下载句柄
    private var once: Bool = false              //  控制失败后是否重新下载
    
    override init() {
        super.init()
        if NSFileManager.defaultManager().fileExistsAtPath(tempPath) {
            try! NSFileManager.defaultManager().removeItemAtPath(tempPath)
        }
        NSFileManager.defaultManager().createFileAtPath(tempPath, contents: nil, attributes: nil)
    }
}

// MARK: - public funcs
extension RequestTask {
    /**
     连接服务器，请求数据（或拼range请求部分数据）（此方法中会将协议头修改为http）
     
     - parameter offset: 请求位置
     */
    public func set(URL url: NSURL, offset: Int) {
        
        func initialTmpFile() {
            try! NSFileManager.defaultManager().removeItemAtPath(tempPath)
            NSFileManager.defaultManager().createFileAtPath(tempPath, contents: nil, attributes: nil)
        }
        
        self.url = url
        self.offset = offset
        
        //  如果建立第二次请求，则需初始化缓冲文件
        if taskArr.count >= 1 {
            initialTmpFile()
        }
        
        //  初始化已下载文件长度
        downLoadingOffset = 0
        
        //  把stream://xxx的头换成http://的头
        let actualURLComponents = NSURLComponents(URL: url, resolvingAgainstBaseURL: false)
        actualURLComponents?.scheme = "http"
        guard let URL = actualURLComponents?.URL else {return}
        let request = NSMutableURLRequest(URL: URL, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringCacheData, timeoutInterval: 20.0)
        
        //  若非从头下载，且视频长度已知且大于零，则下载offset到videoLength的范围（拼request参数）
        if offset > 0 && videoLength > 0 {
            request.addValue("bytes=\(offset)-\(videoLength - 1)", forHTTPHeaderField: "Range")
        }
        
        connection?.cancel()
        connection = NSURLConnection(request: request, delegate: self, startImmediately: false)
        connection?.setDelegateQueue(NSOperationQueue.mainQueue())
        connection?.start()
    }
}

// MARK: - NSURLConnectionDataDelegate
extension RequestTask: NSURLConnectionDataDelegate {
    public func connection(connection: NSURLConnection, didReceiveResponse response: NSURLResponse) {
        isFinishLoad = false
        guard response is NSHTTPURLResponse else {return}
        //  解析头部数据
        let httpResponse = response as! NSHTTPURLResponse
        let dic = httpResponse.allHeaderFields
        let content = dic["Content-Range"] as? String
        let array = content?.componentsSeparatedByString("/")
        let length = array?.last
        //  拿到真实长度
        var videoLength = 0
        if Int(length ?? "0") == 0 {
            videoLength = Int(httpResponse.expectedContentLength)
        } else {
            videoLength = Int(length!)!
        }
        
        self.videoLength = videoLength
        //TODO: 此处需要修改为真实数据格式 - 从字典中取
        self.mimeType = "video/mp4"
        //  回调
        recieveVideoInfoHandler?(task: self, videoLength: videoLength, mimeType: mimeType!)
        //  连接加入到任务数组中
        taskArr.append(connection)
        //  初始化文件传输句柄
        fileHandle = NSFileHandle.init(forWritingAtPath: tempPath)
        print(tempPath)
    }
    
    public func connection(connection: NSURLConnection, didReceiveData data: NSData) {
        //  寻址到文件末尾
        fileHandle?.seekToEndOfFile()
        fileHandle?.writeData(data)
        downLoadingOffset += data.length
        receiveVideoDataHandler?(task: self)
    }
    
    public func connectionDidFinishLoading(connection: NSURLConnection) {
        if taskArr.count < 2 {
            isFinishLoad = true
            let document = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true).last! as NSString
            //TODO: 更新保存路径
            let movePath = document.stringByAppendingPathComponent("保存数据.mp4")
            //TODO: 认为这里应该用move方法，否则应该copy完以后清除tempFile..
            var isSuccessful = true
            do { try NSFileManager.defaultManager().copyItemAtPath(tempPath, toPath: movePath) } catch {
                isSuccessful = false
                print("tmp文件持久化失败")
            }
            if isSuccessful {
                print("持久化文件成功！路径 - \(movePath)")
            }
        }
        receiveVideoFinishHanlder?(task: self)
    }
    
    public func connection(connection: NSURLConnection, didFailWithError error: NSError) {
        if error.code == -1001 && !once {   //  超时，1秒后重连一次
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1), dispatch_get_main_queue(), { 
                self.continueLoading()
            })
        }
        if error.code == -1009 {
            print("无网络连接")
        }
        receiveVideoFailHandler?(task: self,error: error)
    }
}

// MARK: - private functions
extension RequestTask {
    /**
     断线重连
     */
    private func continueLoading() {
        once = true
        guard let url = url else {return}
        let actualURLComponents = NSURLComponents.init(URL: url, resolvingAgainstBaseURL: false)
        actualURLComponents?.scheme = "http"
        guard let URL = actualURLComponents?.URL else {return}
        let request = NSMutableURLRequest(URL: URL, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringCacheData, timeoutInterval: 20.0)
        request.addValue("bytes=\(downLoadingOffset)-\(videoLength - 1)", forHTTPHeaderField: "Range")
        connection?.cancel()
        connection = NSURLConnection(request: request, delegate: self, startImmediately: false)
        connection?.setDelegateQueue(NSOperationQueue.mainQueue())
        connection?.start()
    }
}
