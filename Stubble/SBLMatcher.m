#import "SBLMatcher.h"
#import "SBLArgumentMatcherResult.h"
#import "SBLValueLoggingHelper.h"

typedef void(^SBLMatcherPostInvocationMatchBlock)(SBLInvocationArgument *argument);

@interface SBLMatcher ()<NSCopying>

@property (nonatomic, copy) SBLMatcherBlock matcherBlock;
@property (nonatomic, copy) SBLMatcherPostInvocationMatchBlock postInvocationMatchBlock;
@property (nonatomic, readonly) NSUUID *uuid;
@property (nonatomic, copy) SBLMatcherPlaceholderBlock placeholderBlock;
@property (nonatomic) SBLMatcher *memoryHack;

@end

@implementation SBLMatcher

+ (instancetype)any {
	return [SBLMatcher matcherWithBlock:^SBLArgumentMatcherResult *(SBLInvocationArgument *argument) {
        return [[SBLArgumentMatcherResult alloc] initWithMatches:YES];
	}];
}

+ (instancetype)captor:(void *)captor {
	NSValue *pointerValue = [NSValue valueWithPointer:captor];
	SBLMatcher *matcher = [SBLMatcher any];
    matcher.postInvocationMatchBlock = ^(SBLInvocationArgument *argument) {
        void *captorPointer = [pointerValue pointerValue];
        id capturedArgument = argument.argument;
        
        if (argument.shouldUnbox) {
            [(NSValue *)capturedArgument getValue:captorPointer];
        } else {
            if (SBLIsBlock(capturedArgument)) {
                capturedArgument = [capturedArgument copy];
            }
            __block id __strong *captorId = (id __strong *)captorPointer;
            *captorId = capturedArgument;
        }
    };
    return matcher;
}

+ (instancetype)objectIsEqualMatcher:(id)object {
	return [SBLMatcher matcherWithBlock:^SBLArgumentMatcherResult *(SBLInvocationArgument *argument) {
        BOOL argumentMatches = [object isEqual:argument.argument] || (!object && !argument.argument);
        SBLArgumentMatcherResult *argumentMatcherResult = [[SBLArgumentMatcherResult alloc] initWithMatches:argumentMatches];
        if (!argumentMatches) {
            argumentMatcherResult = [[SBLArgumentMatcherResult alloc] initWithMatches:argumentMatches
                                                             expectedArgument:argument.argument
                                                               actualArgument:object];
        }
        return argumentMatcherResult;
	}];
}

+ (instancetype)matcherWithBlock:(SBLMatcherBlock)matcherBlock {
	SBLMatcher *matcher = [[SBLMatcher alloc] init];
	matcher.matcherBlock = matcherBlock;
	return matcher;
}

+ (instancetype)valueIsEqualMatcher:(NSValue *)value {
	return [SBLMatcher matcherWithBlock:^SBLArgumentMatcherResult *(SBLInvocationArgument *argument) {
        BOOL argumentMatches = [value isEqual:argument.argument];
        SBLArgumentMatcherResult *argumentMatcherResult = [[SBLArgumentMatcherResult alloc] initWithMatches:argumentMatches];
        SBLValueLoggingHelper *valueLoggingHelper = [[SBLValueLoggingHelper alloc] init];
        if (!argumentMatches) {
            NSString *expectedArgument = [valueLoggingHelper stringValueForValue:argument.argument type:argument.type];
            NSString *actualArgument = [valueLoggingHelper stringValueForValue:value type:argument.type];
            argumentMatcherResult = [[SBLArgumentMatcherResult alloc] initWithMatches:argumentMatches
                                                                     expectedArgument:expectedArgument
                                                                       actualArgument:actualArgument];
        }
        return argumentMatcherResult;
	}];
}

- (id)init {
    return [self initWithUUID:[NSUUID UUID]];
}

- (instancetype)initWithUUID:(NSUUID *)uuid {
    if (self = [super init]) {
        _uuid = uuid;
    }
    return self;
}

- (void)postInvocationMatchActionWithArgument:(SBLInvocationArgument *)argument {
    if (self.postInvocationMatchBlock) {
        self.postInvocationMatchBlock(argument);
    }
}

- (SBLArgumentMatcherResult *)matchesArgument:(SBLInvocationArgument *)argument {
	return self.matcherBlock(argument);
}

- (void *)placeholder {
	return (__bridge void *)self;
}

- (NSValue *)placeholderWithType:(char[])type {
	NSValue *placeholderValue = nil;
	if (SBLIsBlockType(type)) {
		__weak typeof(self) weakSelf = self;
		self.memoryHack = self;
		if (!self.placeholderBlock) {
			self.placeholderBlock = ^{return weakSelf;};
		}
		placeholderValue = [NSValue value:&_placeholderBlock withObjCType:type];
	} else if (SBLIsObjectType(type)) {
		self.memoryHack = self;
		SBLMatcher *placeholder = [self placeholder];
		placeholderValue = [NSValue value:&placeholder withObjCType:type];
	} else {
		void *placeholder = NULL;
		placeholderValue = [NSValue value:&placeholder withObjCType:type];
	}
	return placeholderValue;
}

- (void)getValue:(id *)value {
	*value = [self copy];
}

// need to implement this to support matching blocks
- (id)copyWithZone:(NSZone *)zone {
    SBLMatcher *copiedMatcher = [[[self class] allocWithZone:zone] initWithUUID:self.uuid];
    copiedMatcher.matcherBlock = self.matcherBlock;
    return copiedMatcher;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[SBLMatcher class]] && [self.uuid isEqual:[object uuid]];
}

- (BOOL)isBlockPlaceholderForMatcher:(SBLMatcherPlaceholderBlock)block {
	return self.placeholderBlock != nil && block == self.placeholderBlock;
}

- (NSUInteger)hash {
    return [self.uuid hash];
}

@end
