//
//  NSRange+Helpers.swift
//  All Aboard
//
//  Created by Gaurav Bhambhani on 8/4/24.
//

import Foundation

extension NSRange {
  init(_ range: CFRange) {
    self = NSMakeRange(range.location == kCFNotFound ? NSNotFound : range.location, range.length)
  }
}
