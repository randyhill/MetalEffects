//
//  DebugUtils.swift
//  SimpleVideoFilter
//
//  Created by Randy Hill on 3/10/19.
//  Copyright © 2019 Red Queen Coder, LLC. All rights reserved.
//

import Foundation

func DbOnMainThread(_ shouldBeOnMainThread: Bool, function: String = #function, line: Int = #line) {
    if Thread.current.isMainThread != shouldBeOnMainThread{
        DbLog("ON WRONG THREAD", function: function, line: line)
    }
}

private let dbTimeFormatter = DateFormatter()
private func dateString() -> String {
    dbTimeFormatter.dateFormat = "h:m:ss.SSSS"
    return dbTimeFormatter.string(from: Date())
}

func DbLog(_ message: String, function: String = #function, line: Int = #line) {
    print("DBLOG: \(message), at \(function):\(line) at time: \(dateString())")
}

private class ProfileEntry {
    var time: TimeInterval = 0.0
    var count: Int = 0
    
    func incrementTimeBy(_ newTime: TimeInterval) {
        self.time += newTime
        self.count +=  1
    }
    
    func averageTime() -> TimeInterval {
        return time/TimeInterval(count)
    }
}
private var profileKeys = [String: ProfileEntry]()
private var lastTime: Date?
func DbProfilePoint(function: String = #function, line: Int = #line) {
    let key = "\(function):\(line)"
    if let lastTime = lastTime {
        let pointTime = Date().timeIntervalSince(lastTime)
        let entry = profileKeys[key] ?? ProfileEntry()
        entry.incrementTimeBy(pointTime)
        profileKeys[key] = entry
    }
    lastTime = Date()
}

func DbPrintProfileSummary(_ message: String = "", function: String = #function, line: Int = #line) {
    print("Profile Summary: \(message), at \(function):\(line) at time: \(dateString())")
    for (key, entry) in profileKeys {
        let description = String(format: "Ave: %.3f, TotalL %.3f %@", entry.averageTime(), entry.time, key)
        print(description)
    }
    profileKeys.removeAll()
    lastTime = nil
}

func DbAssert(_ isTrue: Bool, function: String = #function, line: Int = #line) {
    if isTrue{
        DbLog("ASSERT FAILED", function: function, line: line)
    }
}
