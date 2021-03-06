////////////////////////////////////////////////////////////////////////////
//
// Copyright 2014 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RLMSchema_Private.h"

#import "RLMAccessor.h"
#import "RLMObject_Private.hpp"
#import "RLMObjectSchema_Private.hpp"
#import "RLMRealm_Private.hpp"
#import "RLMSwiftSupport.h"
#import "RLMUtil.hpp"

#import "object_store.hpp"
#import <objc/runtime.h>
#import <realm/group.hpp>

using namespace realm;

const uint64_t RLMNotVersioned = realm::ObjectStore::NotVersioned;

// RLMSchema private properties
@interface RLMSchema ()
@property (nonatomic, readwrite) NSMutableDictionary *objectSchemaByName;
@end

static RLMSchema *s_sharedSchema;
static NSMutableDictionary *s_localNameToClass;

@implementation RLMSchema

- (RLMObjectSchema *)schemaForClassName:(NSString *)className {
    return _objectSchemaByName[className];
}

- (RLMObjectSchema *)objectForKeyedSubscript:(__unsafe_unretained id<NSCopying> const)className {
    RLMObjectSchema *schema = _objectSchemaByName[className];
    if (!schema) {
        NSString *message = [NSString stringWithFormat:@"Object type '%@' not persisted in Realm", className];
        @throw RLMException(message);
    }
    return schema;
}

- (void)setObjectSchema:(NSArray *)objectSchema {
    _objectSchema = objectSchema;
    _objectSchemaByName = [NSMutableDictionary dictionaryWithCapacity:objectSchema.count];
    for (RLMObjectSchema *object in objectSchema) {
        [(NSMutableDictionary *)_objectSchemaByName setObject:object forKey:object.className];
    }
}

+ (void)initialize {
    static bool initialized;
    if (initialized) {
        return;
    }
    initialized = true;

    NSMutableArray *schemaArray = [NSMutableArray array];
    RLMSchema *schema = [[RLMSchema alloc] init];

    unsigned int numClasses;
    Class *classes = objc_copyClassList(&numClasses);

    // first create class to name mapping so we can do array validation
    // when creating object schema
    s_localNameToClass = [NSMutableDictionary dictionary];
    for (unsigned int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        static Class objectBaseClass = [RLMObjectBase class];
        if (!RLMIsKindOfClass(cls, objectBaseClass) || ![cls shouldPersistToRealm]) {
            continue;
        }

        NSString *className = NSStringFromClass(cls);
        if ([RLMSwiftSupport isSwiftClassName:className]) {
            className = [RLMSwiftSupport demangleClassName:className];
        }
        // NSStringFromClass demangles the names for top-level Swift classes
        // but not for nested classes. _T indicates it's a Swift symbol, t
        // indicates it's a type, and C indicates it's a class.
        else if ([className hasPrefix:@"_TtC"]) {
            NSString *message = [NSString stringWithFormat:@"RLMObject subclasses cannot be nested within other declarations. Please move %@ to global scope.", className];
            @throw RLMException(message);
        }

        if (s_localNameToClass[className]) {
            NSString *message = [NSString stringWithFormat:@"RLMObject subclasses with the same name cannot be included twice in the same target. Please make sure '%@' is only linked once to your current target.", className];
            @throw RLMException(message);
        }
        s_localNameToClass[className] = cls;

        // override classname for all valid classes
        RLMReplaceClassNameMethod(cls, className);
    }

    // process all RLMObject subclasses
    for (Class cls in s_localNameToClass.allValues) {
        RLMObjectSchema *schema = [RLMObjectSchema schemaForObjectClass:cls];
        [schemaArray addObject:schema];

        // override sharedSchema classs methods for performance
        RLMReplaceSharedSchemaMethod(cls, schema);

        // set standalone class on shared shema for standalone object creation
        schema.standaloneClass = RLMStandaloneAccessorClassForObjectClass(schema.objectClass, schema);
    }
    free(classes);

    // set class array
    schema.objectSchema = schemaArray;

    // set shared schema
    s_sharedSchema = schema;
}

// schema based on runtime objects
+ (instancetype)sharedSchema {
    return s_sharedSchema;
}

// schema based on tables in a realm
+ (instancetype)dynamicSchemaFromRealm:(RLMRealm *)realm {
    // generate object schema and class mapping for all tables in the realm
    ObjectStore::Schema objectStoreSchema = ObjectStore::schema_from_group(realm.group);

    // cache descriptors for all subclasses of RLMObject
    NSMutableArray *schemaArray = [NSMutableArray arrayWithCapacity:objectStoreSchema.size()];
    for (unsigned long i = 0; i < objectStoreSchema.size(); i++) {
        [schemaArray addObject:[RLMObjectSchema objectSchemaForObjectStoreSchema:objectStoreSchema[i]]];
    }
    
    // set class array and mapping
    RLMSchema *schema = [RLMSchema new];
    schema.objectSchema = schemaArray;
    return schema;
}

+ (Class)classForString:(NSString *)className {
    if (Class cls = s_localNameToClass[className]) {
        return cls;
    }
    return NSClassFromString(className);
}

- (id)copyWithZone:(NSZone *)zone {
    RLMSchema *schema = [[RLMSchema allocWithZone:zone] init];
    schema.objectSchema = [[NSArray allocWithZone:zone] initWithArray:self.objectSchema copyItems:YES];
    return schema;
}

- (instancetype)shallowCopy {
    RLMSchema *schema = [[RLMSchema alloc] init];
    NSMutableArray *objectSchema = [NSMutableArray arrayWithCapacity:_objectSchema.count];
    for (RLMObjectSchema *schema in _objectSchema) {
        [objectSchema addObject:[schema shallowCopy]];
    }
    schema.objectSchema = objectSchema;
    return schema;
}

- (BOOL)isEqualToSchema:(RLMSchema *)schema {
    if (_objectSchema.count != schema.objectSchema.count) {
        return NO;
    }
    for (RLMObjectSchema *objectSchema in schema.objectSchema) {
        if (![_objectSchemaByName[objectSchema.className] isEqualToObjectSchema:objectSchema]) {
            return NO;
        }
    }
    return YES;
}

- (NSString *)description {
    NSMutableString *objectSchemaString = [NSMutableString string];
    for (RLMObjectSchema *objectSchema in self.objectSchema) {
        [objectSchemaString appendFormat:@"\t%@\n", [objectSchema.description stringByReplacingOccurrencesOfString:@"\n" withString:@"\n\t"]];
    }
    return [NSString stringWithFormat:@"Schema {\n%@}", objectSchemaString];
}

@end
