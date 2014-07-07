//
//  IntroScene.m
//  Smooth Drawing - v3
//

// Import the interfaces
#import "IntroScene.h"
#import "LineDrawer.h"

@implementation IntroScene

+ (IntroScene *)scene {
	return [[self alloc] init];
}

- (id) init {
	self = [super init];
	if (self) {
		CCNode* lineDrawer = [[LineDrawer alloc] init];
		lineDrawer.contentSize = [CCDirector sharedDirector].viewSize;
		lineDrawer.position = CGPointZero;
		lineDrawer.anchorPoint = CGPointZero;
		[self addChild:lineDrawer];
	}
	return self;
}

@end