/*
 * Smooth drawing: http://merowing.info
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
#import <CoreGraphics/CoreGraphics.h>
#import "cocos2d.h"
#import "LineDrawer.h"
#import "CCNode_Private.h" // shader stuff
#import "CCRenderer_private.h" // access to get and stash renderer

#pragma mark - A data structure used during line rendering
typedef struct {
	CGPoint pos;
	CGFloat z;
	ccColor4F color;
} LineVertex;

#pragma mark - A simple class for holding position and width of a point on the line
@interface LinePoint : NSObject
@property(nonatomic, assign) CGPoint pos;
@property(nonatomic, assign) CGFloat width;
@end

@implementation LinePoint
@end

#pragma mark - The main LineDrawer class - creates a CCRenderTexture to draw on based on gesture recognition capturing the users input
@implementation LineDrawer {
	NSMutableArray<LinePoint*>* points;
	NSMutableArray<NSNumber*>* velocities;
	NSMutableArray<LinePoint*>* circlesPoints;
	
	BOOL connectingLine;
	CGPoint prevC, prevD;
	CGPoint prevG;
	CGPoint prevI;
	CGFloat overdraw;
	
	CCRenderTexture *renderTexture;
	BOOL finishingLine;
}

- (id)init
{
	self = [super init];
	if (self) {
		points = [NSMutableArray array];
		velocities = [NSMutableArray array];
		circlesPoints = [NSMutableArray array];
		
		overdraw = 3.0;
		
		CGSize s = [[CCDirector sharedDirector] viewSize];
		renderTexture = [[CCRenderTexture alloc] initWithWidth:s.width height:s.height pixelFormat:CCTexturePixelFormat_RGBA8888];
		
		renderTexture.positionType = CCPositionTypeNormalized;
		renderTexture.anchorPoint = ccp(0, 0);
		renderTexture.position = ccp(0.5, 0.5);
		
		[renderTexture clear:1.0 g:1.0 b:1.0 a:0.0];
		[self addChild:renderTexture];
		
		[[[CCDirector sharedDirector] view] setUserInteractionEnabled:YES];
		
		UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
		panGestureRecognizer.maximumNumberOfTouches = 1;
		[[[CCDirector sharedDirector] view] addGestureRecognizer:panGestureRecognizer];
		
		UILongPressGestureRecognizer *longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
		[[[CCDirector sharedDirector] view] addGestureRecognizer:longPressGestureRecognizer];
	}
	return self;
}

#pragma mark - Handling points
- (void)startNewLineFrom:(CGPoint)newPoint withSize:(CGFloat)aSize
{
	connectingLine = NO;
	[self addPoint:newPoint withSize:aSize];
}

- (void)endLineAt:(CGPoint)aEndPoint withSize:(CGFloat)aSize
{
	[self addPoint:aEndPoint withSize:aSize];
	finishingLine = YES;
}

- (void)addPoint:(CGPoint)newPoint withSize:(CGFloat)size
{
	LinePoint *point = [[LinePoint alloc] init];
	point.pos = newPoint;
	point.width = size;
	[points addObject:point];
}

#pragma mark - Drawing

#define ADD_TRIANGLE(A, B, C, Z) vertices[index].pos = A, vertices[index++].z = Z, vertices[index].pos = B, vertices[index++].z = Z, vertices[index].pos = C, vertices[index++].z = Z

- (void)drawLines:(NSArray<LinePoint*>*)linePoints withColor:(ccColor4F)color
{
	NSUInteger numberOfVertices = (linePoints.count - 1) * 18;
	LineVertex *vertices = calloc(sizeof(LineVertex), numberOfVertices);
	
	CGPoint prevPoint = linePoints[0].pos;
	CGFloat prevValue = linePoints[0].width;
	CGFloat curValue;
	NSInteger index = 0;
	for (NSUInteger i = 1; i < linePoints.count; ++i) {
		LinePoint *pointValue = linePoints[i];
		CGPoint curPoint = pointValue.pos;
		curValue = pointValue.width;
		
		//! equal points, skip them
		if (ccpFuzzyEqual(curPoint, prevPoint, 0.0001)) {
			continue;
		}
		
		CGPoint dir = ccpSub(curPoint, prevPoint);
		CGPoint perpendicular = ccpNormalize(ccpPerp(dir));
		CGPoint A = ccpAdd(prevPoint, ccpMult(perpendicular, prevValue / 2));
		CGPoint B = ccpSub(prevPoint, ccpMult(perpendicular, prevValue / 2));
		CGPoint C = ccpAdd(curPoint, ccpMult(perpendicular, curValue / 2));
		CGPoint D = ccpSub(curPoint, ccpMult(perpendicular, curValue / 2));
		
		//! continuing line
		if (connectingLine || index > 0) {
			A = prevC;
			B = prevD;
		} else if (index == 0) {
			//! circle at start of line, revert direction
			[circlesPoints addObject:pointValue];
			[circlesPoints addObject:linePoints[i - 1]];
		}
		
		ADD_TRIANGLE(A, B, C, 1.0);
		ADD_TRIANGLE(B, C, D, 1.0);
		
		prevD = D;
		prevC = C;
		if (finishingLine && (i == linePoints.count - 1)) {
			[circlesPoints addObject:linePoints[i - 1]];
			[circlesPoints addObject:pointValue];
			finishingLine = NO;
		}
		
		prevPoint = curPoint;
		prevValue = curValue;
		
		//! Add overdraw
		CGPoint F = ccpAdd(A, ccpMult(perpendicular, overdraw));
		CGPoint G = ccpAdd(C, ccpMult(perpendicular, overdraw));
		CGPoint H = ccpSub(B, ccpMult(perpendicular, overdraw));
		CGPoint I = ccpSub(D, ccpMult(perpendicular, overdraw));
		
		//! end vertices of last line are the start of this one, also for the overdraw
		if (connectingLine || index > 6) {
			F = prevG;
			H = prevI;
		}
		
		prevG = G;
		prevI = I;
		
		ADD_TRIANGLE(F, A, G, 2.0);
		ADD_TRIANGLE(A, G, C, 2.0);
		ADD_TRIANGLE(B, H, D, 2.0);
		ADD_TRIANGLE(H, D, I, 2.0);
	}
	
	[self fillLineTriangles:vertices count:index withColor:color];
	
	if (index > 0) {
		connectingLine = YES;
	}
	
	free(vertices);
}

- (void)fillLineEndPointAt:(CGPoint)center direction:(CGPoint)aLineDir radius:(CGFloat)radius andColor:(ccColor4F)color
{
	// Premultiplied alpha.
	color.r *= color.a;
	color.g *= color.a;
	color.b *= color.a;
	ccColor4F fadeOutColor = ccc4f(0, 0, 0, 0);
	
	const NSUInteger numberOfSegments = 32;
	LineVertex *vertices = malloc(sizeof(LineVertex) * numberOfSegments * 9);
	CGFloat anglePerSegment = (CGFloat)(M_PI / (numberOfSegments - 1));
	
	//! we need to cover M_PI from this, dot product of normalized vectors is equal to cos angle between them... and if you include rightVec dot you get to know the correct direction :)
	CGPoint perpendicular = ccpPerp(aLineDir);
	CGFloat angle = acosf(ccpDot(perpendicular, CGPointMake(0, 1)));
	CGFloat rightDot = ccpDot(perpendicular, CGPointMake(1, 0));
	if (rightDot < 0.0) {
		angle *= -1;
	}
	
	CGPoint prevPoint = center;
	CGPoint prevDir = ccp(sinf(0), cosf(0));
	for (NSUInteger i = 0; i < numberOfSegments; ++i) {
		CGPoint dir = ccp(sinf(angle), cosf(angle));
		CGPoint curPoint = ccp(center.x + radius * dir.x, center.y + radius * dir.y);
		vertices[i * 9 + 0].pos = center;
		vertices[i * 9 + 1].pos = prevPoint;
		vertices[i * 9 + 2].pos = curPoint;
		
		//! fill rest of vertex data
		for (NSUInteger j = 0; j < 9; ++j) {
			vertices[i * 9 + j].z = j < 3 ? 1.0 : 2.0;
			vertices[i * 9 + j].color = color;
		}
		
		//! add overdraw
		vertices[i * 9 + 3].pos = ccpAdd(prevPoint, ccpMult(prevDir, overdraw));
		vertices[i * 9 + 3].color = fadeOutColor;
		vertices[i * 9 + 4].pos = prevPoint;
		vertices[i * 9 + 5].pos = ccpAdd(curPoint, ccpMult(dir, overdraw));
		vertices[i * 9 + 5].color = fadeOutColor;
		
		vertices[i * 9 + 6].pos = prevPoint;
		vertices[i * 9 + 7].pos = curPoint;
		vertices[i * 9 + 8].pos = ccpAdd(curPoint, ccpMult(dir, overdraw));
		vertices[i * 9 + 8].color = fadeOutColor;
		
		prevPoint = curPoint;
		prevDir = dir;
		angle += anglePerSegment;
	}
	
	CCRenderer *renderer = [CCRenderer currentRenderer];
	GLKMatrix4 projection;
	[renderer.globalShaderUniforms[CCShaderUniformProjection] getValue:&projection];
	CCRenderBuffer buffer = [renderer enqueueTriangles:numberOfSegments * 3 andVertexes:numberOfSegments * 9 withState:self.renderState globalSortOrder:1];
	
	CCVertex vertex;
	for (NSUInteger i = 0; i < numberOfSegments * 9; i++) {
		vertex.position = GLKVector4Make(vertices[i].pos.x, vertices[i].pos.y, 0.0, 1.0);
		vertex.color = GLKVector4Make(vertices[i].color.r, vertices[i].color.g, vertices[i].color.b, vertices[i].color.a);
		CCRenderBufferSetVertex(buffer, (int)i, CCVertexApplyTransform(vertex, &projection));
	}
	
	for (NSUInteger i = 0; i < numberOfSegments * 3; i++) {
		CCRenderBufferSetTriangle(buffer, (int)i, i*3, (i*3)+1, (i*3)+2);
	}
	
	free(vertices);
}

- (void)fillLineTriangles:(LineVertex *)vertices count:(NSUInteger)count withColor:(ccColor4F)color
{
	if (!count) {
		return;
	}
	
	ccColor4F fullColor = color;
	fullColor.r *= fullColor.a;
	fullColor.g *= fullColor.a;
	fullColor.b *= fullColor.a;
	ccColor4F fadeOutColor = ccc4f(0, 0, 0, 0); // Premultiplied alpha.
	
	for (NSUInteger i = 0; i < count / 18; ++i) {
		for (NSUInteger j = 0; j < 6; ++j) {
			vertices[i * 18 + j].color = fullColor;
		}
		
		//! FAG
		vertices[i * 18 + 6].color = fadeOutColor;
		vertices[i * 18 + 7].color = fullColor;
		vertices[i * 18 + 8].color = fadeOutColor;
		
		//! AGD
		vertices[i * 18 + 9].color = fullColor;
		vertices[i * 18 + 10].color = fadeOutColor;
		vertices[i * 18 + 11].color = fullColor;
		
		//! BHC
		vertices[i * 18 + 12].color = fullColor;
		vertices[i * 18 + 13].color = fadeOutColor;
		vertices[i * 18 + 14].color = fullColor;
		
		//! HCI
		vertices[i * 18 + 15].color = fadeOutColor;
		vertices[i * 18 + 16].color = fullColor;
		vertices[i * 18 + 17].color = fadeOutColor;
	}
	
	CCRenderer *renderer = [CCRenderer currentRenderer];
	
	GLKMatrix4 projection;
	[renderer.globalShaderUniforms[CCShaderUniformProjection] getValue:&projection];
	CCRenderBuffer buffer = [renderer enqueueTriangles:count/3 andVertexes:count withState:self.renderState globalSortOrder:1];
	
	CCVertex vertex;
	for (NSUInteger i = 0; i < count; i++) {
		vertex.position = GLKVector4Make(vertices[i].pos.x, vertices[i].pos.y, 0.0, 1.0);
		vertex.color = GLKVector4Make(vertices[i].color.r, vertices[i].color.g, vertices[i].color.b, vertices[i].color.a);
		CCRenderBufferSetVertex(buffer, (int)i, CCVertexApplyTransform(vertex, &projection));
	}
	
	for (NSUInteger i = 0; i < count/3; i++) {
		CCRenderBufferSetTriangle(buffer, (int)i, i*3, (i*3)+1, (i*3)+2);
	}
	
	for (NSUInteger i = 0; i < circlesPoints.count / 2; ++i) {
		LinePoint *prevPoint = circlesPoints[i * 2];
		LinePoint *curPoint = circlesPoints[i * 2 + 1];
		CGPoint dirVector = ccpNormalize(ccpSub(curPoint.pos, prevPoint.pos));
		
		[self fillLineEndPointAt:curPoint.pos direction:dirVector radius:curPoint.width * 0.5 andColor:color];
	}
	
	[circlesPoints removeAllObjects];
}

- (NSMutableArray<LinePoint*>*)calculateSmoothLinePoints
{
	if (points.count > 2) {
		NSMutableArray<LinePoint*>* smoothedPoints = [NSMutableArray array];
		for (NSUInteger i = 2; i < points.count; ++i) {
			LinePoint *prev2 = points[i - 2];
			LinePoint *prev1 = points[i - 1];
			LinePoint *cur = points[i];
			
			CGPoint midPoint1 = ccpMult(ccpAdd(prev1.pos, prev2.pos), 0.5);
			CGPoint midPoint2 = ccpMult(ccpAdd(cur.pos, prev1.pos), 0.5);
			
			const NSUInteger segmentDistance = 2;
			CGFloat distance = ccpDistance(midPoint1, midPoint2);
			const NSUInteger numberOfSegments = MIN(128, MAX(floorf(distance / segmentDistance), 32));
			
			CGFloat t = 0.0;
			CGFloat step = 1.0 / numberOfSegments;
			for (NSUInteger j = 0; j < numberOfSegments; j++) {
				LinePoint *newPoint = [[LinePoint alloc] init];
				newPoint.pos = ccpAdd(ccpAdd(ccpMult(midPoint1, powf(1 - t, 2)), ccpMult(prev1.pos, 2.0 * (1 - t) * t)), ccpMult(midPoint2, t * t));
				newPoint.width = powf(1 - t, 2) * ((prev1.width + prev2.width) * 0.5) + 2.0 * (1 - t) * t * prev1.width + t * t * ((cur.width + prev1.width) * 0.5);
				
				[smoothedPoints addObject:newPoint];
				t += step;
			}
			LinePoint *finalPoint = [[LinePoint alloc] init];
			finalPoint.pos = midPoint2;
			finalPoint.width = (cur.width + prev1.width) * 0.5;
			[smoothedPoints addObject:finalPoint];
		}
		//! we need to leave last 2 points for next draw
		[points removeObjectsInRange:NSMakeRange(0, points.count - 2)];
		return smoothedPoints;
	} else {
		return nil;
	}
}

#pragma mark This method does the actual drawing of the latest input onto the CCRenderTexture - called by the cocos2d system whenever the LineDrawer node needs updating
- (void)draw:(CCRenderer *)renderer transform:(const GLKMatrix4 *)transform
{
	ccColor4F color = {0, 0.5, 0, 1};
	[renderTexture begin];
	
	NSMutableArray<LinePoint*>* smoothedPoints = [self calculateSmoothLinePoints];
	if (smoothedPoints) {
		[self drawLines:smoothedPoints withColor:color];
	}
	[renderTexture end];
}

#pragma mark - Math to calculate the thickness of the line based on velocity of touch movement

- (CGFloat)extractSize:(UIPanGestureRecognizer *)panGestureRecognizer
{
	//! result of trial & error
	CGFloat vel = ccpLength([panGestureRecognizer velocityInView:panGestureRecognizer.view]);
	CGFloat size = vel / 166.0;
	size = clampf(size, 1, 40);
	
	if ([velocities count] > 1) {
		size = size * 0.2 + [velocities[velocities.count - 1] floatValue] * 0.8;
	}
	
	[velocities addObject:@(size)];
	return size;
}

#pragma mark - GestureRecognizer handling

- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer
{
	const CGPoint point = [[CCDirector sharedDirector] convertToGL:[panGestureRecognizer locationInView:panGestureRecognizer.view]];
	
	if (panGestureRecognizer.state == UIGestureRecognizerStateBegan) {
		[points removeAllObjects];
		[velocities removeAllObjects];
		
		CGFloat size = [self extractSize:panGestureRecognizer];
		
		[self startNewLineFrom:point withSize:size];
		[self addPoint:point withSize:size];
		[self addPoint:point withSize:size];
	}
	
	if (panGestureRecognizer.state == UIGestureRecognizerStateChanged) {
		//! skip points that are too close
		CGFloat eps = 1.5;
		if (points.count > 0) {
			CGFloat length = ccpLength(ccpSub(points.lastObject.pos, point));
			
			if (length < eps) {
				return;
			}
		}
		CGFloat size = [self extractSize:panGestureRecognizer];
		[self addPoint:point withSize:size];
		
		
	}
	
	if (panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
		CGFloat size = [self extractSize:panGestureRecognizer];
		[self endLineAt:point withSize:size];
	}
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPressGestureRecognizer
{
	[renderTexture beginWithClear:1.0 g:1.0 b:1.0 a:0];
	[renderTexture end];
}
@end
