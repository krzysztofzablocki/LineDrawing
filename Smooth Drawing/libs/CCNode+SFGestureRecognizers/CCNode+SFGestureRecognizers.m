//
//  CCNode+GestureRecognizers.m
//  Kubik
//
//  Created by Krzysztof Zablocki on 2/12/12.
//  Copyright (c) 2012 Krzysztof Zablocki. All rights reserved.
//
//
//  ARC Helper
//
//  Version 1.2.2
//
//  Created by Nick Lockwood on 05/01/2012.
//  Copyright 2012 Charcoal Design
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://gist.github.com/1563325

//  Krzysztof Zabłocki Added AH_BRIDGE(x) to bridge cast to void*

#ifndef AH_RETAIN
#if __has_feature(objc_arc)
#define AH_RETAIN(x) (x)
#define AH_RELEASE(x) (void)(x)
#define AH_AUTORELEASE(x) (x)
#define AH_SUPER_DEALLOC (void)(0)
#define AH_BRIDGE(x) ((__bridge void*)x)
#else
#define __AH_WEAK
#define AH_WEAK assign
#define AH_RETAIN(x) [(x) retain]
#define AH_RELEASE(x) [(x) release]
#define AH_AUTORELEASE(x) [(x) autorelease]
#define AH_SUPER_DEALLOC [super dealloc]
#define AH_BRIDGE(x) (x)
#endif
#endif

//  Weak reference support

#ifndef AH_WEAK
#if defined __IPHONE_OS_VERSION_MIN_REQUIRED
#if __IPHONE_OS_VERSION_MIN_REQUIRED > __IPHONE_4_3
#define __AH_WEAK __weak
#define AH_WEAK weak
#else
#define __AH_WEAK __unsafe_unretained
#define AH_WEAK unsafe_unretained
#endif
#elif defined __MAC_OS_X_VERSION_MIN_REQUIRED
#if __MAC_OS_X_VERSION_MIN_REQUIRED > __MAC_10_6
#define __AH_WEAK __weak
#define AH_WEAK weak
#else
#define __AH_WEAK __unsafe_unretained
#define AH_WEAK unsafe_unretained
#endif
#endif
#endif

//  ARC Helper ends

#import "CCNode+SFGestureRecognizers.h"
#import <objc/runtime.h>

//! __ for internal use | check out SFExecuteOnDealloc for category on NSObject that allows the same ;)
typedef void(^__SFExecuteOnDeallocBlock)(void);

@interface __SFExecuteOnDealloc : NSObject
+ (void)executeBlock:(__SFExecuteOnDeallocBlock)aBlock onObjectDealloc:(id)aObject;

- (id)initWithBlock:(__SFExecuteOnDeallocBlock)aBlock;
@end

@implementation __SFExecuteOnDealloc {
@public
  __SFExecuteOnDeallocBlock block;
}

+ (void)executeBlock:(__SFExecuteOnDeallocBlock)aBlock onObjectDealloc:(id)aObject
{
  __SFExecuteOnDealloc *executor = [[self alloc] initWithBlock:aBlock];
  objc_setAssociatedObject(aObject, AH_BRIDGE(executor), executor, OBJC_ASSOCIATION_RETAIN);
  AH_RELEASE(executor);
}

- (id)initWithBlock:(__SFExecuteOnDeallocBlock)aBlock
{
  self = [super init];
  if (self) {
    block = [aBlock copy];
  }
  return self;
}

- (void)dealloc
{
  if (block) {
    block();
  }
  AH_RELEASE(block);
  AH_SUPER_DEALLOC;
}
@end


static NSString *const CCNodeSFGestureRecognizersArrayKey = @"CCNodeSFGestureRecognizersArrayKey";
static NSString *const CCNodeSFGestureRecognizersTouchRect = @"CCNodeSFGestureRecognizersTouchRect";
static NSString *const CCNodeSFGestureRecognizersTouchEnabled = @"CCNodeSFGestureRecognizersTouchEnabled";
static NSString *const UIGestureRecognizerSFGestureRecognizersPassingDelegateKey = @"UIGestureRecognizerSFGestureRecognizersPassingDelegateKey";

@interface __SFGestureRecognizersPassingDelegate : NSObject <UIGestureRecognizerDelegate> {
@public
  __AH_WEAK id <UIGestureRecognizerDelegate> originalDelegate;
  __AH_WEAK CCNode *node;
}
@end

@implementation __SFGestureRecognizersPassingDelegate

#pragma mark - UIGestureRecognizer Delegate handling
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
  CGPoint pt = [[CCDirector sharedDirector] convertToGL:[touch locationInView:[touch view]]];
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  BOOL rslt = [node isPointTouchableInArea:pt];
#else
  BOOL rslt = [node sf_isPointTouchableInArea:pt];
#endif

  //! we need to make sure that no other node ABOVE this one was touched, we want ONLY the top node with gesture recognizer to get callback
  if (rslt) {
    CCNode *curNode = node;
    CCNode *parent = node.parent;
    while (curNode != nil && rslt) {
      CCNode *child;
      BOOL nodeFound = NO;
      CCARRAY_FOREACH(parent.children, child){
        if (!nodeFound) {
          if (!nodeFound && curNode == child) {
            nodeFound = YES;
          }
          continue;
        }
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
        if ([child isNodeInTreeTouched:pt])
#else
        if( [child sf_isNodeInTreeTouched:pt])          
#endif
        {
          rslt = NO;
          break;
        }
      }

      curNode = parent;
      parent = curNode.parent;
    }
  }

  if (rslt && [originalDelegate respondsToSelector:@selector(gestureRecognizer:shouldReceiveTouch:)]) {
    rslt = [originalDelegate gestureRecognizer:gestureRecognizer shouldReceiveTouch:touch];
  }

  return rslt;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if ([originalDelegate respondsToSelector:@selector(gestureRecognizerShouldBegin:)]) {
    return [originalDelegate gestureRecognizerShouldBegin:gestureRecognizer];
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  if ([originalDelegate respondsToSelector:@selector(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)]) {
    return [originalDelegate gestureRecognizer:gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:otherGestureRecognizer];
  }

  return NO;
}

#pragma mark - Handling delegate change
- (void)setDelegate:(id <UIGestureRecognizerDelegate>)aDelegate
{
  __SFGestureRecognizersPassingDelegate *passingDelegate = objc_getAssociatedObject(self, AH_BRIDGE(UIGestureRecognizerSFGestureRecognizersPassingDelegateKey));
  if (passingDelegate) {
    passingDelegate->originalDelegate = aDelegate;
  } else {
    [self performSelector:@selector(originalSetDelegate:) withObject:aDelegate];
  }
}

- (id <UIGestureRecognizerDelegate>)delegate
{
  __SFGestureRecognizersPassingDelegate *passingDelegate = objc_getAssociatedObject(self, AH_BRIDGE(UIGestureRecognizerSFGestureRecognizersPassingDelegateKey));
  if (passingDelegate) {
    return passingDelegate->originalDelegate;
  }

  //! no delegate yet so use original method
  return [self performSelector:@selector(originalDelegate)];
}
@end


@implementation UIGestureRecognizer (SFGestureRecognizers)
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
@dynamic node;
#else
@dynamic sf_node;
#endif

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (CCNode *)node
#else
- (CCNode*)sf_node
#endif
{
  __SFGestureRecognizersPassingDelegate *passingDelegate = objc_getAssociatedObject(self, AH_BRIDGE(UIGestureRecognizerSFGestureRecognizersPassingDelegateKey));
  if (passingDelegate) {
    return passingDelegate->node;
  }
  return nil;
}
@end


@implementation CCNode (SFGestureRecognizers)

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
@dynamic isTouchEnabled;
@dynamic touchRect;
#else
@dynamic sf_isTouchEnabled;
@dynamic sf_touchRect;
#endif

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)addGestureRecognizer:(UIGestureRecognizer *)aGestureRecognizer
#else
- (void)sf_addGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer
#endif
{
  //! prepare passing gesture recognizer
  __SFGestureRecognizersPassingDelegate *passingDelegate = [[__SFGestureRecognizersPassingDelegate alloc] init];
  passingDelegate->originalDelegate = aGestureRecognizer.delegate;
  passingDelegate->node = self;
  aGestureRecognizer.delegate = passingDelegate;
  //! retain passing delegate as it only lives as long as this gesture recognizer lives
  objc_setAssociatedObject(aGestureRecognizer, AH_BRIDGE(UIGestureRecognizerSFGestureRecognizersPassingDelegateKey), passingDelegate, OBJC_ASSOCIATION_RETAIN);
  AH_RELEASE(passingDelegate);

  //! we need to swap gesture recognizer methods so that we can handle delegates nicely, but we also need to be able to call originalMethods if gesture isnt assigned to CCNode, do it only once in whole app
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method originalGetter = class_getInstanceMethod([UIGestureRecognizer class], @selector(delegate));
    Method originalSetter = class_getInstanceMethod([UIGestureRecognizer class], @selector(setDelegate:));
    Method swappedGetter = class_getInstanceMethod([__SFGestureRecognizersPassingDelegate class], @selector(delegate));
    Method swappedSetter = class_getInstanceMethod([__SFGestureRecognizersPassingDelegate class], @selector(setDelegate:));

    class_addMethod([UIGestureRecognizer class], @selector(originalDelegate), method_getImplementation(originalGetter), method_getTypeEncoding(originalGetter));
    class_replaceMethod([UIGestureRecognizer class], @selector(delegate), method_getImplementation(swappedGetter), method_getTypeEncoding(swappedGetter));
    class_addMethod([UIGestureRecognizer class], @selector(originalSetDelegate:), method_getImplementation(originalSetter), method_getTypeEncoding(originalSetter));
    class_replaceMethod([UIGestureRecognizer class], @selector(setDelegate:), method_getImplementation(swappedSetter), method_getTypeEncoding(swappedSetter));
  });


  if ([[CCDirector sharedDirector] respondsToSelector:@selector(view)]) {
    [[[CCDirector sharedDirector] performSelector:@selector(view)] addGestureRecognizer:aGestureRecognizer];
  } else {
    [[[CCDirector sharedDirector] performSelector:@selector(openGLView)] addGestureRecognizer:aGestureRecognizer];
  }
  //! add to array
  NSMutableArray *gestureRecognizers = objc_getAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersArrayKey));
  if (!gestureRecognizers) {
    gestureRecognizers = [NSMutableArray array];
    objc_setAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersArrayKey), gestureRecognizers, OBJC_ASSOCIATION_RETAIN);

  }
  [gestureRecognizers addObject:aGestureRecognizer];

  //! remove this gesture recognizer from view when array is deallocatd
  __AH_WEAK CCNode *weakSelf = self;
  [__SFExecuteOnDealloc executeBlock:^{
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
    [weakSelf removeGestureRecognizer:aGestureRecognizer];
#else
    [weakSelf sf_removeGestureRecognizer:aGestureRecognizer];
#endif
  }                  onObjectDealloc:gestureRecognizers];

#if SF_GESTURE_RECOGNIZERS_AUTO_ENABLE_TOUCH_ON_NEW_GESTURE_RECOGNIZER
  //! enable touch for this element or it won't work
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  [self setIsTouchEnabled:YES];
#else
  [self sf_setIsTouchEnabled:YES];
#endif
#endif
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)removeGestureRecognizer:(UIGestureRecognizer *)aGestureRecognizer
#else
- (void)sf_removeGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer
#endif
{
  NSMutableArray *gestureRecognizers = objc_getAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersArrayKey));
  objc_setAssociatedObject(self, AH_BRIDGE(UIGestureRecognizerSFGestureRecognizersPassingDelegateKey), nil, OBJC_ASSOCIATION_RETAIN);
  if ([[CCDirector sharedDirector] respondsToSelector:@selector(view)]) {
    [[[CCDirector sharedDirector] performSelector:@selector(view)] removeGestureRecognizer:aGestureRecognizer];
  } else {
    [[[CCDirector sharedDirector] performSelector:@selector(openGLView)] removeGestureRecognizer:aGestureRecognizer];
  }
  [gestureRecognizers removeObject:aGestureRecognizer];
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (NSArray *)gestureRecognizers
#else
- (NSArray*)sf_gestureRecognizers
#endif
{
  //! add to array
  NSMutableArray *gestureRecognizers = objc_getAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersArrayKey));
  if (!gestureRecognizers) {
    gestureRecognizers = [NSMutableArray array];
    objc_setAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersArrayKey), gestureRecognizers, OBJC_ASSOCIATION_RETAIN);
  }
  return [NSArray arrayWithArray:gestureRecognizers];
}

#pragma mark - Point inside

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (BOOL)isPointInArea:(CGPoint)pt
#else
- (BOOL)sf_isPointInArea:(CGPoint)pt
#endif
{
  if (!_visible || !_isRunning) {
    return NO;
  }

  //! convert to local space 
  pt = [self convertToNodeSpace:pt];

  //! get touchable rect in local space
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  CGRect rect = self.touchRect;
#else
  CGRect rect = self.sf_touchRect;
#endif

  if (CGRectContainsPoint(rect, pt)) {
    return YES;
  }
  return NO;
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (BOOL)isPointTouchableInArea:(CGPoint)pt
{
  if (!self.isTouchEnabled) {
    return NO;
  } else {
    return [self isPointInArea:pt];
  }
}
#else
- (BOOL)sf_isPointTouchableInArea:(CGPoint)pt
{
  if (!self.sf_isTouchEnabled) {
    return NO;
  } else {
    return [self sf_isPointInArea:pt];
  }
}
#endif


#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (BOOL)isNodeInTreeTouched:(CGPoint)pt
#else
- (BOOL)sf_isNodeInTreeTouched:(CGPoint)pt
#endif
{
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  if ([self isPointTouchableInArea:pt]) {
    return YES;
  }
#else
  if( [self sf_isPointTouchableInArea:pt] ) {
    return YES;
  }
#endif

  BOOL rslt = NO;
  CCNode *child;
  CCARRAY_FOREACH(_children, child ){
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  if ([child isNodeInTreeTouched:pt])
#else
    if( [child sf_isNodeInTreeTouched:pt] )
#endif
  {
    rslt = YES;
    break;
  }
}
  return rslt;
}

#pragma mark - Touch Enabled

- (BOOL)sf_isTouchEnabled
{
  if ([self respondsToSelector:@selector(isTouchEnabled)]) {
    return (BOOL)[self performSelector:@selector(isTouchEnabled)];
  }
  //! our own implementation
  NSNumber *touchEnabled = objc_getAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersTouchEnabled));
  if (!touchEnabled) {
    [self sf_setIsTouchEnabled:NO];
    return NO;
  }
  return [touchEnabled boolValue];
}

- (void)sf_setIsTouchEnabled:(BOOL)aTouchEnabled
{
  if ([self respondsToSelector:@selector(setIsTouchEnabled:)]) {
    [self sf_setIsTouchEnabled:aTouchEnabled];
    return;
  }

  objc_setAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersTouchEnabled), [NSNumber numberWithBool:aTouchEnabled], OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - Touch Rectangle

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)setTouchRect:(CGRect)aRect
#else
- (void)sf_setTouchRect:(CGRect)aRect
#endif
{
  objc_setAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersTouchRect), [NSValue valueWithCGRect:aRect], OBJC_ASSOCIATION_RETAIN);
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (CGRect)touchRect
#else
- (CGRect)sf_touchRect
#endif
{
  NSValue *rectValue = objc_getAssociatedObject(self, AH_BRIDGE(CCNodeSFGestureRecognizersTouchRect));
  if (rectValue) {
    return [rectValue CGRectValue];
  } else {
    CGRect defaultRect = CGRectMake(0, 0, self.contentSize.width, self.contentSize.height);
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
    self.touchRect = defaultRect;
#else 
    self.sf_touchRect = defaultRect;
#endif
    return defaultRect;
  }
}

//! CCLayer has implementation of isTouchEnabled / setIsTouchEnabled, so we only use our internal methods if we are NOT CCLayer subclass 
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
  if (anInvocation.selector == @selector(isTouchEnabled)) {
    anInvocation.selector = @selector(sf_isTouchEnabled);
  } else if (anInvocation.selector == @selector(setIsTouchEnabled:)) {
    anInvocation.selector = @selector(sf_setIsTouchEnabled:);
  }
  [anInvocation invokeWithTarget:self];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
  if (![self respondsToSelector:aSelector]) {
    if (aSelector == @selector(isTouchEnabled)) {
      return [self methodSignatureForSelector:@selector(sf_isTouchEnabled)];
    } else if (aSelector == @selector(setIsTouchEnabled:)) {
      return [self methodSignatureForSelector:@selector(sf_setIsTouchEnabled:)];
    }
  }

  return [super methodSignatureForSelector:aSelector];
}
#endif
@end
