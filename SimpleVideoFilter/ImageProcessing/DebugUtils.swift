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

var profileKeys = [String: TimeInterval]()
var lastTime: Date?
func DbProfilePoint(_ key: String = "", function: String = #function, line: Int = #line) {
    print("Profile Point: \(dateString()), \(key) at \(function):\(line)")
    if let lastTime = lastTime {
        let pointTime = Date().timeIntervalSince(lastTime)
        let previousTime = profileKeys[key] ?? 0.0
        profileKeys[key] = pointTime + previousTime
    }
    lastTime = Date()
}

func DbPrintProfileSummary(_ message: String = "", function: String = #function, line: Int = #line) {
    print("Profile Summary: \(message), at \(function):\(line) at time: \(dateString())")
    for (key, totalTime) in profileKeys {
        print("Total time: %.3f %s", totalTime, key)
    }
    profileKeys.removeAll()
    lastTime = nil
}

func DbAssert(_ isTrue: Bool, function: String = #function, line: Int = #line) {
    if isTrue{
        DbLog("ASSERT FAILED", function: function, line: line)
    }
}
