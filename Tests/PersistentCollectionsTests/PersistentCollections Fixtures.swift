//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import _CollectionsTestSupport
import PersistentCollections

/// A list of example trees to use while testing persistent hash maps.
///
/// Each example has a name and a list of path specifications or collisions.
///
/// A path spec is an ASCII `String` representing the hash of a key/value pair,
/// a.k.a a path in the prefix tree. Each character in the string identifies
/// a bucket index of a tree node, starting from the root.
/// (Encoded in radix 32, with digits 0-9 followed by letters. In order to
/// prepare for a potential reduction in the maximum node size, it is best to
/// keep the digits in the range 0-F.) The prefix tree's depth is limited by the
/// size of hash values.
///
/// For example, the string "5A" corresponds to a key/value pair
/// that is in bucket 10 of a second-level node that is found at bucket 5
/// of the root node.
///
/// Hash collisions are modeled by strings of the form `<path>*<count>` where
/// `<path>` is a path specification, and `<count>` is the number of times that
/// path needs to be repeated. (To implement the collisions, the path is
/// extended with an infinite number of zeroes.)
///
/// To generate input data from these fixtures, the items are sorted into
/// the same order as we expect a preorder walk would visit them in the
/// resulting tree. The resulting ordering is then used to insert key/value
/// pairs into the map, with sequentially increasing keys.
let _fixtures: KeyValuePairs<String, [String]> = [
  "empty": [],
  "single-item": [
    "A"
  ],
  "single-node": [
    "0",
    "1",
    "2",
    "3",
    "4",
    "A",
    "B",
    "C",
    "D",
  ],
  "few-collisions": [
    "42*5"
  ],
  "many-collisions": [
    "42*40"
  ],
  "few-different-collisions": [
    "1*3",
    "21*3",
    "22*3",
    "3*3",
  ],
  "everything-on-the-2nd-level": [
    "00", "01", "02", "03", "04",
    "10", "11", "12", "13", "14",
    "20", "21", "22", "23", "24",
    "30", "31", "32", "33", "34",
  ],
  "two-levels-mixed": [
    "00", "01",
    "2",
    "30", "33",
    "4",
    "5",
    "60", "61", "66",
    "71", "75", "77",
    "8",
    "94", "98", "9A",
    "A3", "A4",
  ],
  "vee": [
    "11110",
    "11115",
    "11119",
    "1111B",
    "66664",
    "66667",
  ],
  "fork": [
    "31110",
    "31115",
    "31119",
    "3111B",
    "36664",
    "36667",
  ],
  "chain-left": [
    "0",
    "10",
    "110",
    "1110",
    "11110",
    "11111",
  ],
  "chain-right": [
    "1",
    "01",
    "001",
    "0001",
    "00001",
    "000001",
  ],
  "expansion0": [
    "00000001*3",
    "00001",
  ],
  "expansion1": [
    "00000001*3",
    "01",
    "00001",
  ],
  "expansion2": [
    "11111111*3",
    "10",
    "11110",
  ],
  "expansion3": [
    "01",
    "00001",
    "00000001*3",
  ],
  "expansion4": [
    "10",
    "11110",
    "11111111*3",
  ],
  "nested": [
    "50",
    "51",
    "520",
    "521",
    "5220",
    "5221",
    "52220",
    "52221",
    "522220",
    "522221",
    "5222220",
    "5222221",
    "52222220",
    "52222221",
    "522222220",
    "522222221",
    "5222222220",
    "5222222221",
    "5222222222",
    "5222222223",
    "522222223",
    "522222224",
    "52222223",
    "52222224",
    "5222223",
    "5222224",
    "522223",
    "522224",
    "52223",
    "52224",
    "5223",
    "5224",
    "53",
    "54",
  ],
  "deep": [
    "0",

    // Deeply nested children with only the leaf containing items
    "1234560",
    "1234561",
    "1234562",
    "1234563",

    "22",
    "25",
  ],
]

let fixtures: [Fixture] = _fixtures.map {
  Fixture(title: $0, contents: $1)
}

struct Fixture {
  let title: String
  let itemsInIterationOrder: [RawCollider]
  let itemsInInsertionOrder: [RawCollider]

  init(title: String, contents: [String]) {
    self.title = title

    let maxDepth = PersistentDictionary<Int, Int>._maxDepth

    func normalized(_ path: String) -> String {
      precondition(path.unicodeScalars.count < maxDepth)
      let c = Swift.max(0, maxDepth - path.unicodeScalars.count)
      return path.uppercased() + String(repeating: "0", count: c)
    }

    var items: [(path: String, item: RawCollider)] = []
    var seen: Set<String> = []
    for var path in contents {
      if let i = path.unicodeScalars.firstIndex(of: "*") {
        // We need to extend the path of collisions with zeroes to
        // make sure they sort correctly.
        let p = String(path.unicodeScalars.prefix(upTo: i))
        guard let count = Int(path.suffix(from: i).dropFirst(), radix: 10)
        else { fatalError("Invalid item: '\(path)'") }
        path = normalized(p)
        let hash = Hash(path)!
        for _ in 0 ..< count {
          items.append((path, RawCollider(items.count, hash)))
        }
      } else {
        path = normalized(path)
        let hash = Hash(path)!
        items.append((path, RawCollider(items.count, hash)))
      }

      if !seen.insert(path).inserted {
        fatalError("Unexpected duplicate path: '\(path)'")
      }
    }

    var seenPrefixes: Set<Substring> = []
    var collidingPrefixes: Set<Substring> = []
    for p in items {
      assert(p.path.count == maxDepth)
      for i in p.path.indices {
        let prefix = p.path[..<i]
        if !seenPrefixes.insert(prefix).inserted {
          collidingPrefixes.insert(prefix)
        }
      }
      if !seenPrefixes.insert(p.path[...]).inserted {
        collidingPrefixes.insert(p.path[...])
      }
    }

    self.itemsInInsertionOrder = items.map { $0.item }

    // Sort paths into the order that we expect items will appear in the
    // dictionary.
    items.sort { a, b in
      var i = a.path.startIndex
      var j = b.path.startIndex
      while i < a.path.endIndex && j < b.path.endIndex {
        let ac = collidingPrefixes.contains(a.path[...i])
        let bc = collidingPrefixes.contains(b.path[...j])
        switch (ac, bc) {
        case (true, false): return false
        case (false, true): return true
        default: break
        }
        if a.path[i] < b.path[j] { return true }
        if a.path[j] > b.path[j] { return false }
        a.path.formIndex(after: &i)
        b.path.formIndex(after: &j)
      }
      precondition(i == a.path.endIndex && j == b.path.endIndex)
      return false
    }

    self.itemsInIterationOrder = items.map { $0.item }
  }

  var count: Int { itemsInInsertionOrder.count }
}

func withEachFixture(
  _ label: String = "fixture",
  body: (Fixture) -> Void
) {
  for fixture in fixtures {
    let entry = TestContext.current.push("\(label): \(fixture.title)")
    defer { TestContext.current.pop(entry) }

    body(fixture)
  }
}

extension LifetimeTracker {
  func persistentSet<Element: Hashable>(
    for fixture: Fixture,
    with transform: (RawCollider) -> Element
  ) -> (
    map: PersistentSet<LifetimeTracked<Element>>,
    ref: [LifetimeTracked<Element>]
  ) {
    let ref = fixture.itemsInIterationOrder.map { key in
      self.instance(for: transform(key))
    }
    let ref2 = fixture.itemsInInsertionOrder.map { key in
      self.instance(for: transform(key))
    }
    return (PersistentSet(ref2), ref)
  }

  func persistentSet(
    for fixture: Fixture
  ) -> (
    map: PersistentSet<LifetimeTracked<RawCollider>>,
    ref: [LifetimeTracked<RawCollider>]
  ) {
    persistentSet(for: fixture) { key in key }
  }

  func persistentDictionary<Key, Value>(
    for fixture: Fixture,
    keyTransform: (RawCollider) -> Key,
    valueTransform: (RawCollider) -> Value
  ) -> (
    map: PersistentDictionary<LifetimeTracked<Key>, LifetimeTracked<Value>>,
    ref: [(key: LifetimeTracked<Key>, value: LifetimeTracked<Value>)]
  ) {
    let ref = fixture.itemsInIterationOrder.map { item in
      let key = keyTransform(item)
      let value = valueTransform(item)
      return (key: self.instance(for: key), value: self.instance(for: value))
    }
    let ref2 = fixture.itemsInInsertionOrder.map { item in
      let key = keyTransform(item)
      let value = valueTransform(item)
      return (key: self.instance(for: key), value: self.instance(for: value))
    }
    return (PersistentDictionary(uniqueKeysWithValues: ref2), ref)
  }

  func persistentDictionary(
    for fixture: Fixture
  ) -> (
    map: PersistentDictionary<LifetimeTracked<RawCollider>, LifetimeTracked<Int>>,
    ref: [(key: LifetimeTracked<RawCollider>, value: LifetimeTracked<Int>)]
  ) {
    persistentDictionary(
      for: fixture,
      keyTransform: { $0 },
      valueTransform: { $0.identity + 1000 })
  }
}
