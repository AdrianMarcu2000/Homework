
//
//  Formatters.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Date formatter used to display homework item timestamps
let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

let compactDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
}()
