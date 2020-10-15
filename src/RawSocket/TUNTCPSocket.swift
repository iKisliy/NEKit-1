import Foundation
import tun2socks

/// The TCP socket build upon `TSTCPSocket`.
///
/// - warning: This class is not thread-safe.
public class TUNTCPSocket: RawTCPSocketProtocol, TSTCPSocketDelegate {
    fileprivate let tsSocket: TSTCPSocket
    fileprivate var reading = false
    fileprivate var pendingReadData: Data = Data()
        fileprivate var remainWriteData: Data = Data()
    fileprivate var remainWriteLength: Int = 0
    fileprivate var sliceSize: Int = 0
        var writeSig = DispatchSemaphore(value: 1)
        var writeLock = NSLock()
        static var  TID:Int = 1
    fileprivate var writeQueue = DispatchQueue.init(label: "TCP Data Write", qos: .default)
    fileprivate var closeAfterWriting = false

    fileprivate var scanner: StreamScanner?

    fileprivate var readLength: Int?

    /**
     Initailize an instance with `TSTCPSocket`.

     - parameter socket: The socket object to work with.
     */
    public init(socket: TSTCPSocket) {
        tsSocket = socket
        tsSocket.delegate = self
        TUNTCPSocket.TID += 1
        NSLog("---------> Create new socket [\(TUNTCPSocket.TID)] th[\(Thread.current)]")
    }

    // MARK: RawTCPSocketProtocol implementation

    /// The `RawTCPSocketDelegate` instance.
    public weak var delegate: RawTCPSocketDelegate?

    /// If the socket is connected.
    public var isConnected: Bool {
        return tsSocket.isConnected
    }

    /// The source address.
    public var sourceIPAddress: IPAddress? {
        return IPAddress(fromInAddr: tsSocket.sourceAddress)
    }

    /// The source port.
    public var sourcePort: Port? {
        return Port(port: tsSocket.sourcePort)
    }

    /// The destination address.
    public var destinationIPAddress: IPAddress? {
        return IPAddress(fromInAddr: tsSocket.destinationAddress)
    }

    /// The destination port.
    public var destinationPort: Port? {
        return Port(port: tsSocket.destinationPort)
    }

    /// `TUNTCPSocket` cannot connect to anything actively, this is just a stub method.
    ///
    /// - Parameters:
    ///   - host: host
    ///   - port: port
    ///   - enableTLS: enableTLS
    ///   - tlsSettings: tlsSettings
    /// - Throws: Never throws anything.
    public func connectTo(host: String, port: Int, enableTLS: Bool, tlsSettings: [AnyHashable: Any]?) throws {}

    /**
     Disconnect the socket.

     The socket will disconnect elegantly after any queued writing data are successfully sent.
     */
    public func disconnect() {
        if !isConnected {
            delegate?.didDisconnectWith(socket: self)
        } else {
            closeAfterWriting = true
            checkStatus()
        }
    }

    /**
     Disconnect the socket immediately.
     */
    public func forceDisconnect() {
        if !isConnected {
            delegate?.didDisconnectWith(socket: self)
        } else {
            tsSocket.close()
        }
    }

    /**
     Send data to local.

     - parameter data: Data to send.
     - warning: This should only be called after the last write is finished, i.e., `delegate?.didWriteData()` is called.
     */
    
        func splitWrite(){
                self.writeQueue.async {
                        while self.remainWriteData.count > 0{
                                NSLog("--------->[\(TUNTCPSocket.TID)] split write and wait th[\(Thread.current)]")
                                self.writeSig.wait()
                                let buf_size = Int(self.tsSocket.writeBufSize())
                                if buf_size == 0{
                                        NSLog("--------->[\(TUNTCPSocket.TID)] buffer is 0 th[\(Thread.current)]")
                                        continue
                                }
                                NSLog("--------->[\(TUNTCPSocket.TID)] get buffer[\(buf_size)] th[\(Thread.current)]")
                                let data_size = self.remainWriteData.count
                                if buf_size > data_size{
                                        self.queueCall{self.tsSocket.writeData(self.remainWriteData)}
                                        self.remainWriteLength = data_size
                                        self.remainWriteData.removeAll()
                                        NSLog("--------->[\(TUNTCPSocket.TID)] the last slice[\(data_size)] th[\(Thread.current)]")
                                        return
                                }
                                NSLog("--------->[\(TUNTCPSocket.TID)] too many slice[\(data_size)] th[\(Thread.current)]")
                                let slice = self.remainWriteData[0 ..< buf_size]
                                self.remainWriteData = self.remainWriteData[buf_size ..< data_size]
                                self.remainWriteLength = buf_size
                                self.queueCall{self.tsSocket.writeData(slice)}
                                NSLog("--------->[\(TUNTCPSocket.TID)] write slice again and remain[\(self.remainWriteData.count)] th[\(Thread.current)]")
                        }
                }
        }
        
        public func write(data: Data) {
                self.writeLock.lock()
                defer{self.writeLock.unlock()}
                
                let data_size = data.count
                let buf_size = Int(self.tsSocket.writeBufSize())
                self.remainWriteLength += data_size
                NSLog("--------->[\(TUNTCPSocket.TID)<--->\(Thread.current)] start write[\(data.count)] buffer is[\(buf_size)]]")
                if data_size <= buf_size{
                        self.tsSocket.writeData(data)
                        return
                }
                
                
                let slice = data[0 ..< buf_size]
                let remain = data[buf_size ..< data_size]
                self.remainWriteData.append(remain)
                self.tsSocket.writeData(slice)
                self.sliceSize = buf_size
                NSLog("--------->[\(TUNTCPSocket.TID)<--->\(Thread.current)] ****** need split slice[\(buf_size)] remain[\(remain.count)]")
                
//                let data_size = data.count
//                let buf_size = Int(self.tsSocket.writeBufSize())
//                NSLog("--------->[\(TUNTCPSocket.TID)] start to write[\(data_size)] buffer is[\(buf_size)] remain[\(self.remainWriteLength)] th[\(Thread.current)]")
//
//                if buf_size > data_size{
//                        self.remainWriteLength = data_size
//                        self.tsSocket.writeData(data)
//                        return
//                }
//
//                NSLog("--------->[\(TUNTCPSocket.TID)] ****** need to split write [\(data_size)] buffer is[\(buf_size)] th[\(Thread.current)]")
//                if buf_size == 0{
//                        NSLog("--------->[\(TUNTCPSocket.TID)] xxxxxx must be err buf_size is 0 th[\(Thread.current)]")
//                        self.remainWriteData.append(data)
//                        return
//                }
//
//
//                let slice = data[0 ..< buf_size]
//                let remain = data[buf_size ..< data_size]
//                self.remainWriteData.append(remain)
//                self.remainWriteLength = buf_size
//                self.tsSocket.writeData(slice)
//                self.splitWrite()
//                NSLog("--------->[\(TUNTCPSocket.TID)] split write remaind[\(remain.count)]th[\(Thread.current)]")
        }

    /**
     Read data from the socket.

     - warning: This should only be called after the last read is finished, i.e., `delegate?.didReadData()` is called.
     */
    public func readData() {
        reading = true
        checkReadData()
    }

    /**
     Read specific length of data from the socket.

     - parameter length: The length of the data to read.
     - warning: This should only be called after the last read is finished, i.e., `delegate?.didReadData()` is called.
     */
    public func readDataTo(length: Int) {
        readLength = length
        reading = true
        checkReadData()
    }

    /**
     Read data until a specific pattern (including the pattern).

     - parameter data: The pattern.
     - warning: This should only be called after the last read is finished, i.e., `delegate?.didReadData()` is called.
     */
    public func readDataTo(data: Data) {
        readDataTo(data: data, maxLength: 0)
    }

    /**
     Read data until a specific pattern (including the pattern).

     - parameter data: The pattern.
     - parameter maxLength: Ignored since `GCDAsyncSocket` does not support this. The max length of data to scan for the pattern.
     - warning: This should only be called after the last read is finished, i.e., `delegate?.didReadData()` is called.
     */
    public func readDataTo(data: Data, maxLength: Int) {
        reading = true
        scanner = StreamScanner(pattern: data, maximumLength: maxLength)
        checkReadData()
    }

    fileprivate func queueCall(_ block: @escaping () -> Void) {
        QueueFactory.getQueue().async(execute: block)
    }

    fileprivate func checkReadData() {
        if pendingReadData.count > 0 {
            queueCall {
                guard self.reading else {
                    // no queued read request
                    return
                }

                if let readLength = self.readLength {
                    if self.pendingReadData.count >= readLength {
                        let returnData = self.pendingReadData.subdata(in: 0..<readLength)
                        self.pendingReadData = self.pendingReadData.subdata(in: readLength..<self.pendingReadData.count)

                        self.readLength = nil
                        self.delegate?.didRead(data: returnData, from: self)
                        self.reading = false
                    }
                } else if let scanner = self.scanner {
                    guard let (match, rest) = scanner.addAndScan(self.pendingReadData) else {
                        return
                    }

                    self.scanner = nil

                    guard let matchData = match else {
                        // do not find match in the given length, stop now
                        return
                    }

                    self.pendingReadData = rest
                    self.delegate?.didRead(data: matchData, from: self)
                    self.reading = false
                } else {
                    self.delegate?.didRead(data: self.pendingReadData, from: self)
                    self.pendingReadData = Data()
                    self.reading = false
                }
            }
        }
    }

    fileprivate func checkStatus() {
        if closeAfterWriting && self.remainWriteLength == 0 {
            forceDisconnect()
        }
    }

    // MARK: TSTCPSocketDelegate implementation
    // The local stop sending anything.
    // Theoretically, the local may still be reading data from remote.
    // However, there is simply no way to know if the local is still open, so we can only assume that the local side close tx only when it decides that it does not need to read anymore.
    open func localDidClose(_ socket: TSTCPSocket) {
        disconnect()
    }

    open func socketDidReset(_ socket: TSTCPSocket) {
        socketDidClose(socket)
    }

    open func socketDidAbort(_ socket: TSTCPSocket) {
        socketDidClose(socket)
    }

    open func socketDidClose(_ socket: TSTCPSocket) {
        queueCall {
            self.delegate?.didDisconnectWith(socket: self)
            self.delegate = nil
        }
    }

    open func didReadData(_ data: Data, from: TSTCPSocket) {
        queueCall {
            self.pendingReadData.append(data)
            self.checkReadData()
        }
    }

        open func didWriteData(_ length: Int, from: TSTCPSocket) {
                
                queueCall{
                        self.writeLock.lock()
                        defer{self.writeLock.unlock()}
                        
                        self.remainWriteLength -= length
                        let remain_size = self.remainWriteData.count
                        
                        if  remain_size > 0{
                                self.sliceSize -= length
                                let buf_size = Int(self.tsSocket.writeBufSize())
                                NSLog("--------->[\(TUNTCPSocket.TID)<--->\(Thread.current)] remaind to process [\(remain_size)] buffer[\(buf_size)]")
                                if self.sliceSize > 0{
                                        return
                                }
                                
                                if buf_size > remain_size{
                                        self.tsSocket.writeData(self.remainWriteData)
                                        self.sliceSize = remain_size
                                        self.remainWriteData.removeAll()
                                        NSLog("--------->[\(TUNTCPSocket.TID)<--->\(Thread.current)] last piece")
                                }else{
                                        let slice = self.remainWriteData[0 ..< buf_size]
                                        self.remainWriteData = self.remainWriteData[buf_size ..< remain_size]
                                        self.sliceSize = buf_size
                                        self.tsSocket.writeData(slice)
                                        NSLog("--------->[\(TUNTCPSocket.TID)<--->\(Thread.current)] go on piece\(buf_size)")
                                }
                                return
                        }
                        
                        if self.remainWriteLength <= 0{
                                self.delegate?.didWrite(data: nil, by: self)
                                self.checkStatus()
                        }
                        NSLog("--------->[\(TUNTCPSocket.TID)<--->\(Thread.current)] didWriteData[\(length)] remain is[\(self.remainWriteLength)]")
                }
                
                
//                        let buf_size = self.tsSocket.writeBufSize()
//                        NSLog("--------->[\(TUNTCPSocket.TID)] didWriteData length [\(length)] buffer[\(buf_size)] remain[\(self.remainWriteLength)] th[\(Thread.current)]")
//
//                        guard self.remainWriteLength <= 0 else{
//                                NSLog("--------->[\(TUNTCPSocket.TID)] go on[\(self.remainWriteLength)]")
//                                return
//                        }
//
//                        guard self.remainWriteData.count == 0 else{
//                                NSLog("--------->[\(TUNTCPSocket.TID)] write finish [\(self.remainWriteLength)] remain[\(self.remainWriteData.count)]")
//                                self.writeSig.signal()
//                                return
//                        }
                        
                
    }
}
