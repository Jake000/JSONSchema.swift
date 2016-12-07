//
//  Validators.swift
//  JSONSchema
//
//  Created by Kyle Fuller on 07/03/2015.
//  Copyright (c) 2015 Cocode. All rights reserved.
//

import Foundation

public enum ValidationResult {
  case valid
  case invalid([Error])
  
  public var isValid: Bool {
    switch self {
    case .valid:
      return true
    case .invalid:
      return false
    }
  }
  
  public var errors: [Error]? {
    switch self {
    case .valid:
      return nil
    case .invalid(let errors):
      return errors
    }
  }
}

extension Collection where Iterator.Element == ValidationResult {
  
  func flattened() -> ValidationResult {
    var errors: [Error] = []
    for result in self {
      if case .invalid(let e) = result {
        errors += e
      }
    }
    return errors.isEmpty ? .valid : .invalid(errors)
  }
}

typealias LegacyValidator = (Any) -> (Bool)
typealias Validator = (Any) -> (ValidationResult)

/// Creates a Validator which always returns an valid result
func validValidation(_ value: Any) -> ValidationResult {
  return .valid
}

/// Creates a Validator which always returns an invalid result with the given error
func invalidValidation(_ error: Error) -> (_ value: Any) -> ValidationResult {
  return { value in
    return .invalid([error])
  }
}

// MARK: Shared

/// Validate the given value is of the given type
func validateType(_ type: String) -> (_ value: Any) -> ValidationResult {
  return { value in
    switch type {
    case "integer":
      if let number = value as? NSNumber {
        if !CFNumberIsFloatType(number) && CFGetTypeID(number) != CFBooleanGetTypeID() {
          return .valid
        }
      }
    case "number":
      if let number = value as? NSNumber {
        if CFGetTypeID(number) != CFBooleanGetTypeID() {
          return .valid
        }
      }
    case "string":
      if value is String {
        return .valid
      }
    case "object":
      if value is NSDictionary {
        return .valid
      }
    case "array":
      if value is NSArray {
        return .valid
      }
    case "boolean":
      if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
          return .valid
        }
      }
    case "null":
      if value is NSNull {
        return .valid
      }
    default:
      break
    }
    
    return .invalid([UnmatchingTypeError(value: value, expectedType: type)])
  }
}

/// Validate the given value is one of the given types
func validateType(_ type: [String]) -> Validator {
  return anyOf(type.map(validateType) as [Validator])
}

func validateType(_ type: Any) -> Validator {
  return (type as? String).map(validateType)
    ?? (type as? [String]).map(validateType)
    ?? invalidValidation(InvalidTypeError(value: type))
}


/// Validate that a value is valid for any of the given validation rules
func anyOf(_ validators: [Validator], error: Error? = nil) -> (_ value: Any) -> ValidationResult {
  return { value in
    return validators.contains(where: { $0(value).isValid }) ? .valid
      : error.map { .invalid([$0]) } ?? .invalid([AnyOfError(value: value)])
  }
}

func oneOf(_ validators: [Validator]) -> (_ value: Any) -> ValidationResult {
  return { value in
    let numberOfValid = validators
      .map    { $0(value) }
      .filter { $0.isValid }.count
    
    return numberOfValid == 1
      ? .valid
      : .invalid([OneOfError(numberOfPassingValidations: numberOfValid)])
  }
}

/// Creates a validator that validates that the given validation rules are not met
func not(_ validator: @escaping Validator) -> (_ value: Any) -> ValidationResult {
  return { value in
    return validator(value).isValid ? .invalid([NotError(value: value)]) : .valid
  }
}

func allOf(_ validators: [Validator]) -> (_ value: Any) -> ValidationResult {
  return { value in
    return validators.map { $0(value) }.flattened()
  }
}

func validateEnum(_ values: [Any]) -> (_ value: Any) -> ValidationResult {
  return { value in
    if let values = values as? [NSObject], let value = value as? NSObject, values.contains(value) {
      return .valid
    }
    return .invalid([EnumError(value: value, values: values)])
  }
}

// MARK: String

func validateLength(_ comparator: @escaping ((Int, Int) -> (Bool)), length: Int, error: Error) -> (_ value: Any) -> ValidationResult {
  return { value in
    if let value = value as? String {
      if !comparator(value.characters.count, length) {
        return .invalid([error])
      }
    }
    return .valid
  }
}

func validatePattern(_ pattern: String) -> (_ value: Any) -> ValidationResult {
  return { value in
    guard let value = value as? String else {
      return .valid
    }
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return .invalid([InvalidRegexError(pattern: pattern)])
    }
    guard expression.matches(in: value, range: NSRange(location: 0, length: value.characters.count)).count != 0 else {
      return .invalid([UnmatchingRegexError(value: value, pattern: pattern)])
    }
    return .valid
  }
}

// MARK: Numerical

func validateMultipleOf(_ number: Double) -> (_ value: Any) -> ValidationResult {
  return { value in
    guard let value = value as? Double, number > 0 else { return .valid }
    let result = value / number
    guard result == floor(result) else {
      return .invalid([MultipleOfError(value: value, number: number)])
    }
    return .valid
  }
}

func validateNumericLength(_ length: Double, comparator: @escaping ((Double, Double) -> (Bool)), exclusiveComparator: @escaping ((Double, Double) -> (Bool)), exclusive: Bool?, error: Error) -> (_ value: Any) -> ValidationResult {
  return { value in
    guard let value = value as? Double else { return .valid }
    if exclusive ?? false {
      if !exclusiveComparator(value, length) {
        return .invalid([error])
      }
    }
    if !comparator(value, length) {
      return .invalid([error])
    }
    return .valid
  }
}

// MARK: Array

func validateArrayLength(_ rhs: Int, comparator: @escaping ((Int, Int) -> Bool), error: Error) -> (_ value: Any) -> ValidationResult {
  return { value in
    if let value = value as? [Any], !comparator(value.count, rhs) {
      return .invalid([error])
    }
    return .valid
  }
}

func validateUniqueItems(_ value: Any) -> ValidationResult {
  guard let value = value as? [Any] else { return .valid }
  
  // 1 and true, 0 and false are isEqual for NSNumber's, so logic to count for that below
  let isBoolean: (NSNumber) -> Bool = { CFGetTypeID($0) != CFBooleanGetTypeID() }
  let numbers = value.flatMap { $0 as? NSNumber }
  let booleans = numbers.filter(isBoolean).map { $0 as Bool }
  let nonBooleans = numbers.filter { !isBoolean($0) }
  let hasTrueAndOne = booleans.filter { $0 }.count > 0 && nonBooleans.filter { $0 == 1 }.count > 0
  let hasFalseAndZero = booleans.filter { !$0 }.count > 0 && nonBooleans.filter { $0 == 0 }.count > 0
  let delta = (hasTrueAndOne ? 1 : 0) + (hasFalseAndZero ? 1 : 0)
  
  if (NSSet(array: value).count + delta) == value.count {
    return .valid
  }
  return .invalid([UniqueItemsError(value: value)])
}

// MARK: Object

func validatePropertiesLength(_ length: Int, comparator: @escaping ((Int, Int) -> (Bool)), error: Error) -> (_ value: Any)  -> ValidationResult {
  return { value in
    if let value = value as? JSON, !comparator(length, value.count) {
      return .invalid([error])
    }
    return .valid
  }
}

func validateRequired(_ required: [String]) -> (_ value: Any)  -> ValidationResult {
  return { value in
    if let value = value as? JSON, !required.contains(where: { !value.keys.contains($0) }) {
      return .valid
    }
    return .invalid([RequiredError(required: required)])
  }
}

func validateProperties(_ properties: [String: Validator]?, patternProperties: [String: Validator]?, additionalProperties: Validator?) -> (_ value: Any) -> ValidationResult {
  return { value in
    guard let value = value as? JSON else { return .valid }
    
    var keys: Set<String> = []
    var results: [ValidationResult] = []
    
    for (key, validator) in properties ?? [:] {
      keys.insert(key)
      if let value = value[key] {
        results.append(validator(value))
      }
    }
    
    for (pattern, validator) in patternProperties ?? [:] {
      do {
        let expression = try NSRegularExpression(pattern: pattern)
        let matchingKeys = value.keys.filter {
          expression.matches(in: $0, range: NSRange(location: 0, length: $0.characters.count)).count > 0
        }
        keys.formUnion(matchingKeys)
        results += matchingKeys.map { validator(value[$0]!) }
      } catch {
        return .invalid([InvalidRegexError(pattern: pattern)])
      }
    }
    
    if let additionalProperties = additionalProperties {
      results += value.keys
        .filter { !keys.contains($0) }
        .map { additionalProperties(value[$0]!) }
    }
    
    return results.flattened()
  }
}

func validateDependency(_ key: String, validator: @escaping LegacyValidator) -> (_ value: Any) -> Bool {
  return { value in
    guard let value = value as? JSON else { return true }
    if let _ = value[key] {
      return validator(value)
    }
    return true
  }
}

func validateDependencies(_ key: String, dependencies: [String]) -> (_ value: Any) -> Bool {
  return { value in
    guard let value = value as? JSON, let _ = value[key] else { return true }
    if dependencies.contains(where: { value[$0] == nil }) {
      return false
    }
    return true
  }
}

// MARK: Format

func validateIPv4(_ value: Any) -> ValidationResult {
  guard let ipv4 = value as? String else { return .valid }
  if let expression = try? NSRegularExpression(pattern: "^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
    if expression.matches(in: ipv4, range: NSRange(location: 0, length: ipv4.characters.count)).count == 1 {
      return .valid
    }
  }
  
  return .invalid([InvalidIPError(value: ipv4, version: .v4)])
}

func validateIPv6(_ value: Any) -> ValidationResult {
  guard let ipv6 = value as? String else { return .valid }
  let capacity = Int(INET6_ADDRSTRLEN)
  var buf = UnsafeMutablePointer<Int8>.allocate(capacity: capacity)
  defer { buf.deinitialize(); buf.deallocate(capacity: capacity) }
  if inet_pton(AF_INET6, ipv6, &buf) == 1 {
    return .valid
  }
  return .invalid([InvalidIPError(value: ipv6, version: .v6)])
}
