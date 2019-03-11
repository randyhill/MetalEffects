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
    print("ERROR: \(message), at \(function):\(line) \(dateString())")
}


func DbProfilePoint(_ message: String = "", function: String = #function, line: Int = #line) {
    print("Profile Point: \(dateString()), \(message) at \(function):\(line)")
}
