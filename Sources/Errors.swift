//
//  Errors.swift
//  JSONSchema
//
//  Created by Jake on 30/11/16.
//  Copyright © 2016 Cocode. All rights reserved.
//

import Foundation

public struct UnmatchingTypeError: LocalizedError {
  public let value: Any
  public let expectedType: String
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("unmatching_types_format", tableName: "JSONSchema", value: "'%1$@' is not of type '%2$@'.", comment: "Unmatching types"), "\(value)", expectedType)
  }
}

public struct InvalidTypeError: LocalizedError {
  public let value: Any
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("invalid_type_format", tableName: "JSONSchema", value: "'%1$@' is not a valid 'type'.", comment: "Invalid type"), "\(value)")
  }
}

public struct AnyOfError: LocalizedError {
  public let value: Any
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("any_of_format", tableName: "JSONSchema", value: "'%1$@' does not meet anyOf validation rules.", comment: "Any of"), "\(value)")
  }
}

public struct OneOfError: LocalizedError {
  public let numberOfPassingValidations: Int
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("one_of_format", tableName: "JSONSchema", value: "%1$ld validations passed instead of only 1.", comment: "One of"), numberOfPassingValidations)
  }
}

public struct NotError: LocalizedError {
  public let value: Any
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("not_format", tableName: "JSONSchema", value: "'%1$@' validated when it is should not.", comment: "Not"), "\(value)")
  }
}

public struct EnumError: LocalizedError {
  public let value: Any
  public let values: [Any]
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("public enum_format", tableName: "JSONSchema", value: "'%1$@' is not a valid public enumeration value of '%2$@'.", comment: "public enum"), "\(value)", "\(values)")
  }
}

public struct UnmatchingRegexError: LocalizedError {
  public let value: String
  public let pattern: String
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("unmatching_regex_format", tableName: "JSONSchema", value: "'%1$@' does not match pattern: '%2$@'.", comment: "Unmatching regular expression"), value, pattern)
  }
}

public struct InvalidRegexError: LocalizedError {
  public let pattern: String
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("invalid_regex_format", tableName: "JSONSchema", value: "[Schema] Regex pattern '%1$@' is not valid.", comment: "Invalid regular expression"), pattern)
  }
}

public struct MultipleOfError: LocalizedError {
  public let value: Double
  public let number: Double
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("multiple_of_format", tableName: "JSONSchema", value: "%1$f is not a multiple of %2$f.", comment: "Multiple of"), value, number)
  }
}

public struct UniqueItemsError: LocalizedError {
  public let value: [Any]
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("unique_items_format", tableName: "JSONSchema", value: "%1$@ does not have unique items.", comment: "Unique items"), "\(value)")
  }
}

public struct RequiredError: LocalizedError {
  public let required: [String]
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("required_format", tableName: "JSONSchema", value: "Required properties are missing '%1$@'.", comment: "Required"), "\(required)")
  }
}

public struct InvalidIPError: LocalizedError {
  public let value: String
  public let version: Version
  
  public enum Version {
    case v4, v6
  }
  
  public var localizedDescription: String {
    switch version {
    case .v4:
      return String.localizedStringWithFormat(NSLocalizedString("ipv4_format", tableName: "JSONSchema", value: "'%1$@' is not a valid IPv4 address.", comment: "IPv4"), value)
    case .v6:
      return String.localizedStringWithFormat(NSLocalizedString("ipv6_format", tableName: "JSONSchema", value: "'%1$@' is not a valid IPv6 address.", comment: "IPv6"), value)
    }
    
  }
}

public struct ReferenceNotFoundError: LocalizedError {
  public let reference: String
  public let component: SchemaKey
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("reference_not_found_format", tableName: "JSONSchema", value: "Reference nt found '%1$@' in '%2$@'.", comment: "Reference not found"), component.rawValue, reference)
  }
}

public struct RemoteReferenceUnsupportedError: LocalizedError {
  public let reference: String
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("remote_reference_unsupported_format", tableName: "JSONSchema", value: "Remote $ref '%1$@' is not yet supported.", comment: "Remote reference unsupported"), reference)
  }
}

public struct LengthError: LocalizedError {
  public let length: Int
  public let itemType: ItemType
  public let comparison: Comparison
  
  public enum ItemType {
    case string, array, properties
  }
  
  public enum Comparison {
    case tooLarge, tooSmall
  }
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat({
      switch (itemType, comparison) {
      case (.string, .tooLarge):
        return NSLocalizedString("string_too_large_format", tableName: "JSONSchema", value: "Length of string is larger than maximum length of %1$ld.", comment: "String too large")
      case (.string, .tooSmall):
        return NSLocalizedString("string_too_small_format", tableName: "JSONSchema", value: "Length of string is smaller than minimum length of %1$ld.", comment: "String too small")
      case (.array, .tooLarge):
        return NSLocalizedString("array_too_large_format", tableName: "JSONSchema", value: "Length of array is larger than maximum length of %1$ld.", comment: "Array too large")
      case (.array, .tooSmall):
        return NSLocalizedString("array_too_small_format", tableName: "JSONSchema", value: "Length of array is smaller than minimum length of %1$ld.", comment: "Array too small")
      case (.properties, .tooLarge):
        return NSLocalizedString("properties_too_large_format", tableName: "JSONSchema", value: "The number of properties is larger than maximum number of %1$ld.", comment: "Properties too large")
      case (.properties, .tooSmall):
        return NSLocalizedString("properties_too_small_format", tableName: "JSONSchema", value: "The number of properties is smaller than minimum number of %1$ld.", comment: "Properties too small")
      }}(), length)
  }
}

public struct ValueBoundsError: LocalizedError {
  public let bounds: Double
  public let comparison: Comparison
  
  public enum Comparison {
    case tooLarge, tooSmall
  }
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat({
      switch comparison {
      case .tooLarge:
        return NSLocalizedString("value_too_large_format", tableName: "JSONSchema", value: "Value exceeds the maximum value of %1$f.", comment: "Value too large")
      case .tooSmall:
        return NSLocalizedString("value_too_small_format", tableName: "JSONSchema", value: "Value is lower than the minimum value of %1$f.", comment: "Value too small")
      }}(), bounds)
  }
}

public struct AdditionalPropertiesError: LocalizedError {
  let itemType: ItemType
  
  enum ItemType {
    case array, object
  }
  
  public var localizedDescription: String {
    switch itemType {
    case .array:
      return NSLocalizedString("array_additional_properties", tableName: "JSONSchema", value: "Additional results are not permitted in this array.", comment: "Array additional properties")
    case .object:
      return NSLocalizedString("object_additional_properties", tableName: "JSONSchema", value: "Additional results are not permitted in this object.", comment: "Object additional properties")
    }
  }
}

public struct DependencyMissingError: LocalizedError {
  public let key: String
  public let dependency: String
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("dependency_missing_format", tableName: "JSONSchema", value: "'%1$@' is missing it's dependency of '%2$@'.", comment: "Dependency missing"), key, dependency)
  }
}

public struct FormatUnsupportedError: LocalizedError {
  public let format: String
  
  public var localizedDescription: String {
    return String.localizedStringWithFormat(NSLocalizedString("format_unsupported_format", tableName: "JSONSchema", value: "'format' validation of '%1$@' is not yet supported.", comment: "Format unsupported"), format)
  }
}
