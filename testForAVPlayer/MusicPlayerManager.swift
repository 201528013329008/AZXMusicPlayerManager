//
//  MusicPlayerManager.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/10.
//  Copyright © 2016年 ymh. All rights reserved.
//
//  TODO: 断点下载、线程优化、支持视频流播放

import AVFoundation
import Foundation
import UIKit

public class MusicPlayerManager: NSObject {
    
    
    //  public var status
    
    public var currentURL: NSURL? {
        get {
            guard let currentIndex = currentIndex, musicURLList = musicURLList where currentIndex < musicURLList.count else {return nil}
            return musicURLList[currentIndex]
        }
    }
    
    /**播放状态，用于需要获取播放器状态的地方KVO*/
    public var status: ManagerStatus = .Non
    /**播放进度*/
    public var progress: CGFloat {
        get {
            if playDuration > 0 {
                let progress = playTime / playDuration
                return progress
            } else {
                return 0
            }
        }
    }
    /**已播放时长*/
    public var playTime: CGFloat = 0
    /**总时长*/
    public var playDuration: CGFloat = CGFloat.max
    /**缓冲时长*/
    public var tmpTime: CGFloat = 0
    
    public var playEndConsul: (()->())?
    /**强引用控制器，防止被销毁*/
    public var currentController: UIViewController?
    
    //  private status
    private var currentIndex: Int?
    private var currentItem: AVPlayerItem? {
        get {
            if let currentURL = currentURL {
                let item = getPlayerItem(withURL: currentURL)
                return item
            } else {
                return nil
            }
        }
    }
    
    private var musicURLList: [NSURL]?
    
    //  basic element
    public var player: AVPlayer?
    
    private var playerStatusObserver: NSObject?
    private var resourceLoader: RequestLoader = RequestLoader()
    private var currentAsset: AVURLAsset?
    private var progressCallBack: ((tmpProgress: Float?, playProgress: Float?)->())?
    
    public class var sharedInstance: MusicPlayerManager {
        struct Singleton {
            static let instance = MusicPlayerManager()
        }
        //  后台播放
        let session = AVAudioSession.sharedInstance()
        do { try session.setActive(true) } catch { print(error) }
        do { try session.setCategory(AVAudioSessionCategoryPlayback) } catch { print(error) }
        return Singleton.instance
    }
    
    public enum ManagerStatus {
        case Non, LoadSongInfo, ReadyToPlay, Play, Pause, Stop
    }
}

// MARK: - basic public funcs
extension MusicPlayerManager {
    /**
     开始播放
     */
    public func play(musicURL: NSURL?) {
        guard let musicURL = musicURL else {return}
        if let index = getIndexOfMusic(music: musicURL) {   //   歌曲在队列中，则按顺序播放
            currentIndex = index
        } else {
            putMusicToArray(music: musicURL)
            currentIndex = 0
        }
        playMusicWithCurrentIndex()
    }
    
    public func play(musicURL: NSURL?, callBack: ((tmpProgress: Float?, playProgress: Float?)->())?) {
        play(musicURL)
        progressCallBack = callBack
    }
    
    public func next() {
        currentIndex = getNextIndex()
        playMusicWithCurrentIndex()
    }
    
    public func previous() {
        currentIndex = getPreviousIndex()
        playMusicWithCurrentIndex()
    }
    /**
     继续
     */
    public func goOn() {
        player?.rate = 1
    }
    /**
     暂停 - 可继续
     */
    public func pause() {
        player?.rate = 0
    }
    /**
     停止 - 无法继续
     */
    public func stop() {
        endPlay()
    }
}

// MARK: - private funcs
extension MusicPlayerManager {
    
    private func putMusicToArray(music URL: NSURL) {
        if musicURLList == nil {
            musicURLList = [URL]
        } else {
            musicURLList!.insert(URL, atIndex: 0)
        }
    }
    
    private func getIndexOfMusic(music URL: NSURL) -> Int? {
        let index = musicURLList?.indexOf(URL)
        return index
    }
    
    private func getNextIndex() -> Int? {
        if let musicURLList = musicURLList where musicURLList.count > 0 {
            if let currentIndex = currentIndex where currentIndex + 1 < musicURLList.count {
                return currentIndex + 1
            } else {
                return 0
            }
        } else {
            return nil
        }
    }
    
    private func getPreviousIndex() -> Int? {
        if let currentIndex = currentIndex {
            if currentIndex - 1 >= 0 {
                return currentIndex - 1
            } else {
                return musicURLList?.count ?? 1 - 1
            }
        } else {
            return nil
        }
    }
    
    /**
     从头播放音乐列表
     */
    private func replayMusicList() {
        guard let musicURLList = musicURLList where musicURLList.count > 0 else {return}
        currentIndex = 0
        playMusicWithCurrentIndex()
    }
    /**
     播放当前音乐
     */
    private func playMusicWithCurrentIndex() {
        guard let currentURL = currentURL else {return}
        //  结束上一首
        endPlay()
        player = AVPlayer(playerItem: getPlayerItem(withURL: currentURL))
        observePlayingItem()
    }
    /**
     本地不存在，返回nil，否则返回本地URL
     */
    private func getLocationFilePath(url: NSURL) -> NSURL? {
        let fileName = url.lastPathComponent
        let path = StreamAudioConfig.audioDicPath + "/\(fileName ?? "tmp.mp4")"
        if NSFileManager.defaultManager().fileExistsAtPath(path) {
            let url = NSURL.init(fileURLWithPath: path)
            return url
        } else {
            return nil
        }
    }
    
    private func getPlayerItem(withURL musicURL: NSURL) -> AVPlayerItem {
        
        if let locationFile = getLocationFilePath(musicURL) {
            let item = AVPlayerItem(URL: locationFile)
            return item
        } else {
            let playURL = resourceLoader.getURL(url: musicURL)!  //  转换协议头
            let asset = AVURLAsset(URL: playURL)
            currentAsset = asset
            asset.resourceLoader.setDelegate(resourceLoader, queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
            let item = AVPlayerItem(asset: asset)
            return item
        }
    }
    
    private func setupPlayer(withURL musicURL: NSURL) {
        let songItem = getPlayerItem(withURL: musicURL)
        player = AVPlayer(playerItem: songItem)
    }
    
    private func playerPlay() {
        player?.play()
    }
    
    private func endPlay() {
        status = ManagerStatus.Stop
        player?.rate = 0
        removeObserForPlayingItem()
        player?.replaceCurrentItemWithPlayerItem(nil)
        resourceLoader.cancel()
        currentAsset?.resourceLoader.setDelegate(nil, queue: nil)
        
        progressCallBack = nil
        resourceLoader = RequestLoader()
        playDuration = 0
        playTime = 0
        playEndConsul?()
        player = nil
    }
}

extension MusicPlayerManager {
    public override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard object is AVPlayerItem else {return}
        let item = object as! AVPlayerItem
        if keyPath == "status" {
            if item.status == AVPlayerItemStatus.ReadyToPlay {
                status = .ReadyToPlay
                print("ReadyToPlay")
                let duration = item.duration
                playerPlay()
                print(duration)
            } else if item.status == AVPlayerItemStatus.Failed {
                status = .Stop
                print("Failed")
                stop()
            }
        } else if keyPath == "loadedTimeRanges" {
            let array = item.loadedTimeRanges
            guard let timeRange = array.first?.CMTimeRangeValue else {return}  //  缓冲时间范围
            let totalBuffer = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)    //  当前缓冲长度
            tmpTime = CGFloat(tmpTime)
            print("共缓冲 - \(totalBuffer)")
            let tmpProgress = tmpTime / playDuration
            progressCallBack?(tmpProgress: Float(tmpProgress), playProgress: nil)
        }
    }
    
    private func observePlayingItem() {
        guard let currentItem = self.player?.currentItem else {return}
        //  KVO监听正在播放的对象状态变化
        currentItem.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.New, context: nil)
        //  监听player播放情况
        playerStatusObserver = player?.addPeriodicTimeObserverForInterval(CMTimeMake(1, 1), queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), usingBlock: { [weak self] (time) in
            guard let `self` = self else {return}
            //  获取当前播放时间
            self.status = .Play
            let currentTime = CMTimeGetSeconds(time)
            let totalTime = CMTimeGetSeconds(currentItem.duration)
            self.playDuration = CGFloat(totalTime)
            self.playTime = CGFloat(currentTime)
            print("current time ---- \(currentTime) ---- tutalTime ---- \(totalTime)")
            self.progressCallBack?(tmpProgress: nil, playProgress: Float(self.progress))
            if totalTime - currentTime < 0.1 {
                self.endPlay()
            }
            }) as? NSObject
        //  监听缓存情况
        currentItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: NSKeyValueObservingOptions.New, context: nil)
    }
    
    private func removeObserForPlayingItem() {
        guard let currentItem = self.player?.currentItem else {return}
        currentItem.removeObserver(self, forKeyPath: "status")
        if playerStatusObserver != nil {
            player?.removeTimeObserver(playerStatusObserver!)
            playerStatusObserver = nil
        }
        currentItem.removeObserver(self, forKeyPath: "loadedTimeRanges")
    }
}

public struct StreamAudioConfig {
    static let audioDicPath: String = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true).last! + "/streamAudio"  //  缓冲文件夹
    static let tempPath: String = audioDicPath + "/temp.mp4"    //  缓冲文件路径 - 非持久化文件路径 - 当前逻辑下，有且只有一个缓冲文件
    
}