/*
 * CCNode+SFGestureRecognizers for cocos2d: http://merowing.info
 *
 * Copyright (c) 2012 Krzysztof Zabłocki
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */
#import "cocos2d.h"

//! do you want to use sf_method or just method, disable shorthand if you have problems with methods names duplication from other code
#define SF_GESTURE_RECOGNIZERS_USE_SHORTHAND 1

//! when you add gesture recognizer to any node it will set isTouchEnabled on this node
#define SF_GESTURE_RECOGNIZERS_AUTO_ENABLE_TOUCH_ON_NEW_GESTURE_RECOGNIZER 0


@interface UIGestureRecognizer (SFGestureRecognizers)
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
@property(nonatomic, readonly) CCNode *node;
#else
@property (nonatomic, readonly) CCNode *sf_node;
#endif
@end

@interface CCNode (SFGestureRecognizers)

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
@property(nonatomic, assign) BOOL isTouchEnabled;
@property(nonatomic, assign) CGRect touchRect;

- (void)addGestureRecognizer:(UIGestureRecognizer *)aGestureRecognizer;

- (void)removeGestureRecognizer:(UIGestureRecognizer *)aGestureRecognizer;

- (NSArray *)gestureRecognizers;

// check if point is in touch area, node is visible and running and isTouchEnabled is set 
- (BOOL)isPointTouchableInArea:(CGPoint)pt;

- (BOOL)isNodeInTreeTouched:(CGPoint)pt;

// check if point is in touch area, node is visible and running, ignores isTouchEnabled
- (BOOL)isPointInArea:(CGPoint)pt;
#else
@property (nonatomic, assign, setter=sf_setIsTouchEnabled:) BOOL sf_isTouchEnabled;
@property (nonatomic, assign, setter=sf_setTouchRect:) CGRect sf_touchRect;

- (void)sf_addGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer;
- (void)sf_removeGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer;
- (NSArray*)sf_gestureRecognizers;

// check if point is in touch area, node is visible and running and isTouchEnabled is set 
- (BOOL)sf_isPointTouchableInArea:(CGPoint)pt;
- (BOOL)sf_isNodeInTreeTouched:(CGPoint)pt;

// check if point is in touch area, node is visible and running, ignores isTouchEnabled
- (BOOL)sf_isPointInArea:(CGPoint)pt;
#endif
@end
