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

typedef struct _LineVertex {
  CGPoint pos;
  float z;
  ccColor4F color;
} LineVertex;

@interface LinePoint : NSObject
@property(nonatomic, assign) CGPoint pos;
@property(nonatomic, assign) float width;
@end


@implementation LinePoint
@synthesize pos;
@synthesize width;
@end

@interface Line  : NSObject {
@public
  NSMutableArray *points;
  NSMutableArray *velocities;
  NSMutableArray *circlesPoints;
	
  BOOL connectingLine;
  CGPoint prevC, prevD;
  CGPoint prevG;
  CGPoint prevI;
  float overdraw;
	
  BOOL finishingLine;
	
	CGPoint currentGLPoint;
	CGPoint prevPoint;
	NSTimeInterval prevTime;
}

@end

@implementation Line
@end


@interface LineDrawer ()

- (void)fillLineTriangles:(LineVertex *)vertices count:(NSUInteger)count withColor:(ccColor4F)color forLine:(Line*)line;

- (void)addPoint:(CGPoint)newPoint withSize:(CGFloat)size toLine:(Line*)line;

- (void)drawLines:(NSArray *)linePoints withColor:(ccColor4F)color forLine:(Line*) line;

@end

@implementation LineDrawer {
	NSMutableDictionary *lines;
  CCRenderTexture *renderTexture;
}

+(NSString*) idForTouch:(UITouch*)touch {
	NSString *touchDesc = [touch description];
	// <UITouch: 0x20039290>
	NSString *touchId = [touchDesc substringWithRange:NSMakeRange(10, 10)];
	return touchId;
}


- (id)init
{
  self = [super init];
  if (self) {
		lines = [NSMutableDictionary dictionary];

		CGSize s = [[CCDirector sharedDirector] viewSize];
    renderTexture = [[CCRenderTexture alloc] initWithWidth:s.width height:s.height pixelFormat:CCTexturePixelFormat_RGBA8888];
		
		renderTexture.positionType = CCPositionTypeNormalized;
    renderTexture.anchorPoint = ccp(0, 0);
    renderTexture.position = ccp(0.5f, 0.5f);

    [renderTexture clear:1.0f g:1.0f b:1.0f a:1.0f];
    [self addChild:renderTexture];

		[[[CCDirector sharedDirector] view] setUserInteractionEnabled:YES];
		[[[CCDirector sharedDirector] view] setMultipleTouchEnabled:YES];
		[self setMultipleTouchEnabled:YES];
		[self setUserInteractionEnabled:YES];

    UILongPressGestureRecognizer *longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [[[CCDirector sharedDirector] view] addGestureRecognizer:longPressGestureRecognizer];
  }
  return self;
}

#pragma mark - Handling touches

- (void)touchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
	CGPoint location = [touch locationInNode:self];
	CGPoint gl_location = [[CCDirector sharedDirector] convertTouchToGL:touch];
	Line *line = [[Line alloc] init];
	line->points = [NSMutableArray array];
	line->velocities = [NSMutableArray array];
	line->circlesPoints = [NSMutableArray array];
	line->overdraw = 3.0f;
	line->connectingLine = NO;
	line->prevTime = touch.timestamp;
	line->prevPoint = location;
	line->currentGLPoint = gl_location;
	CGFloat size = [self extractSize:touch forLine:line];
	[self addPoint:gl_location withSize:size toLine:line];
	[self addPoint:gl_location withSize:size toLine:line];
	[self addPoint:gl_location withSize:size toLine:line];
	NSString *touch_id = [LineDrawer idForTouch:touch];
	[lines setObject:line forKey:touch_id];
}

- (void)touchMoved:(UITouch *)touch withEvent:(UIEvent *)event
{
	NSString *touch_id = [LineDrawer idForTouch:touch];
	Line *line = [lines objectForKey:touch_id];
	//! skip points that are too close
	float eps = 1.5f;
	CGPoint location = [touch locationInNode:self];
	CGPoint gl_location = [[CCDirector sharedDirector] convertTouchToGL:touch];
	if ([line->points count] > 0) {
		float length = ccpLength(ccpSub([(LinePoint *)[line->points lastObject] pos], gl_location));
		if (length < eps) {
			return;
		}
	}
	line->currentGLPoint = gl_location;
	float size = [self extractSize:touch forLine:line];
	[self addPoint:location	withSize:size toLine:line];
}

- (void)touchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
	NSString *touch_id = [LineDrawer idForTouch:touch];
	Line *line = [lines objectForKey:touch_id];
	CGPoint gl_location = [[CCDirector sharedDirector] convertTouchToGL:touch];
	CGFloat size = [self extractSize:touch forLine:line];
	[self addPoint:gl_location withSize:size toLine:line];
	line->finishingLine = YES;
}

- (void)touchCancelled:(UITouch *)touch withEvent:(UIEvent *)event {
	NSLog(@"ccTouchesCancelled: THIS HAPPENS WHEN YOU ALLOW MULTI-TOUCH GESTURES ON IPAD, TURN THEM OFF! SEE ALSO WHAT MIGHT CAUSE IT ON IPHONE/IPOD TOUCH");
	NSLog(@"also happens with long-press canceling stuff, which is a little annoying/awkward. and...what else? maybe a phone call or something?");
	[self touchEnded:touch withEvent:event];
}

- (void)addPoint:(CGPoint)newPoint withSize:(CGFloat)size toLine:(Line*) line {
  LinePoint *point = [[LinePoint alloc] init];
  point.pos = newPoint;
  point.width = size;
  [line->points addObject:point];
}


#pragma mark - Drawing

#define ADD_TRIANGLE(A, B, C, Z) vertices[index].pos = A, vertices[index++].z = Z, vertices[index].pos = B, vertices[index++].z = Z, vertices[index].pos = C, vertices[index++].z = Z

- (void)drawLines:(NSArray *)linePoints withColor:(ccColor4F)color forLine:(Line*) line
{
  unsigned long numberOfVertices = ([linePoints count] - 1) * 18;
  LineVertex *vertices = calloc(sizeof(LineVertex), numberOfVertices);

  CGPoint prevPoint = [(LinePoint *)[linePoints objectAtIndex:0] pos];
  float prevValue = [(LinePoint *)[linePoints objectAtIndex:0] width];
  float curValue;
  int index = 0;
  for (int i = 1; i < [linePoints count]; ++i) {
    LinePoint *pointValue = [linePoints objectAtIndex:i];
    CGPoint curPoint = [pointValue pos];
    curValue = [pointValue width];

    //! equal points, skip them
    if (ccpFuzzyEqual(curPoint, prevPoint, 0.0001f)) {
      continue;
    }

    CGPoint dir = ccpSub(curPoint, prevPoint);
    CGPoint perpendicular = ccpNormalize(ccpPerp(dir));
    CGPoint A = ccpAdd(prevPoint, ccpMult(perpendicular, prevValue / 2));
    CGPoint B = ccpSub(prevPoint, ccpMult(perpendicular, prevValue / 2));
    CGPoint C = ccpAdd(curPoint, ccpMult(perpendicular, curValue / 2));
    CGPoint D = ccpSub(curPoint, ccpMult(perpendicular, curValue / 2));

    //! continuing line
    if (line->connectingLine || index > 0) {
      A = line->prevC;
      B = line->prevD;
    } else if (index == 0) {
      //! circle at start of line, revert direction
      [line->circlesPoints addObject:pointValue];
      [line->circlesPoints addObject:[linePoints objectAtIndex:i - 1]];
    }

    ADD_TRIANGLE(A, B, C, 1.0f);
    ADD_TRIANGLE(B, C, D, 1.0f);

    line->prevD = D;
    line->prevC = C;
    if (line->finishingLine && (i == [linePoints count] - 1)) {
      [line->circlesPoints addObject:[linePoints objectAtIndex:i - 1]];
      [line->circlesPoints addObject:pointValue];
      line->finishingLine = NO;
    }
    prevPoint = curPoint;
    prevValue = curValue;

    //! Add overdraw
    CGPoint F = ccpAdd(A, ccpMult(perpendicular, line->overdraw));
    CGPoint G = ccpAdd(C, ccpMult(perpendicular, line->overdraw));
    CGPoint H = ccpSub(B, ccpMult(perpendicular, line->overdraw));
    CGPoint I = ccpSub(D, ccpMult(perpendicular, line->overdraw));

    //! end vertices of last line are the start of this one, also for the overdraw
    if (line->connectingLine || index > 6) {
      F = line->prevG;
      H = line->prevI;
    }

    line->prevG = G;
    line->prevI = I;

    ADD_TRIANGLE(F, A, G, 2.0f);
    ADD_TRIANGLE(A, G, C, 2.0f);
    ADD_TRIANGLE(B, H, D, 2.0f);
    ADD_TRIANGLE(H, D, I, 2.0f);
  }
  [self fillLineTriangles:vertices count:index withColor:color forLine:line];

  if (index > 0) {
    line->connectingLine = YES;
  }

  free(vertices);
}

- (void)fillLineEndPointAt:(CGPoint)center direction:(CGPoint)aLineDir radius:(CGFloat)radius andColor:(ccColor4F)color forLine:(Line*)line
{
  int numberOfSegments = 32;
  LineVertex *vertices = malloc(sizeof(LineVertex) * numberOfSegments * 9);
  float anglePerSegment = (float)(M_PI / (numberOfSegments - 1));

  //! we need to cover M_PI from this, dot product of normalized vectors is equal to cos angle between them... and if you include rightVec dot you get to know the correct direction :)
  CGPoint perpendicular = ccpPerp(aLineDir);
  float angle = acosf(ccpDot(perpendicular, CGPointMake(0, 1)));
  float rightDot = ccpDot(perpendicular, CGPointMake(1, 0));
  if (rightDot < 0.0f) {
    angle *= -1;
  }

  CGPoint prevPoint = center;
  CGPoint prevDir = ccp(sinf(0), cosf(0));
  for (unsigned int i = 0; i < numberOfSegments; ++i) {
    CGPoint dir = ccp(sinf(angle), cosf(angle));
    CGPoint curPoint = ccp(center.x + radius * dir.x, center.y + radius * dir.y);
    vertices[i * 9 + 0].pos = center;
    vertices[i * 9 + 1].pos = prevPoint;
    vertices[i * 9 + 2].pos = curPoint;

    //! fill rest of vertex data
    for (unsigned int j = 0; j < 9; ++j) {
      vertices[i * 9 + j].z = j < 3 ? 1.0f : 2.0f;
      vertices[i * 9 + j].color = color;
    }

    //! add overdraw
    vertices[i * 9 + 3].pos = ccpAdd(prevPoint, ccpMult(prevDir, line->overdraw));
    vertices[i * 9 + 3].color.a = 0;
    vertices[i * 9 + 4].pos = prevPoint;
    vertices[i * 9 + 5].pos = ccpAdd(curPoint, ccpMult(dir, line->overdraw));
    vertices[i * 9 + 5].color.a = 0;

    vertices[i * 9 + 6].pos = prevPoint;
    vertices[i * 9 + 7].pos = curPoint;
    vertices[i * 9 + 8].pos = ccpAdd(curPoint, ccpMult(dir, line->overdraw));
    vertices[i * 9 + 8].color.a = 0;

    prevPoint = curPoint;
    prevDir = dir;
    angle += anglePerSegment;
  }

  CCRenderer *renderer = [CCRenderer currentRenderer];
  GLKMatrix4 projection;
  [renderer.globalShaderUniforms[CCShaderUniformProjection] getValue:&projection];
  CCRenderBuffer buffer = [renderer enqueueTriangles:numberOfSegments * 3 andVertexes:numberOfSegments * 9 withState:self.renderState globalSortOrder:1];

  CCVertex vertex;
  for (int i = 0; i < numberOfSegments * 9; i++) {
    vertex.position = GLKVector4Make(vertices[i].pos.x, vertices[i].pos.y, 0.0, 1.0);
    vertex.color = GLKVector4Make(vertices[i].color.r, vertices[i].color.g, vertices[i].color.b, vertices[i].color.a);
    CCRenderBufferSetVertex(buffer, i, CCVertexApplyTransform(vertex, &projection));
  }
	
  for (unsigned int i = 0; i < numberOfSegments * 3; i++) {
    CCRenderBufferSetTriangle(buffer, i, i*3, (i*3)+1, (i*3)+2);
  }

  free(vertices);
}

- (void)fillLineTriangles:(LineVertex *)vertices count:(NSUInteger)count withColor:(ccColor4F)color forLine:(Line*)line
{
  if (!count) {
    return;
  }

  ccColor4F fullColor = color;
  ccColor4F fadeOutColor = color;
  fadeOutColor.a = 0;

  for (int i = 0; i < count / 18; ++i) {
    for (int j = 0; j < 6; ++j) {
      vertices[i * 18 + j].color = color;
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
	for (unsigned int i = 0; i < count; i++) {
    vertex.position = GLKVector4Make(vertices[i].pos.x, vertices[i].pos.y, 0.0, 1.0);
    vertex.color = GLKVector4Make(vertices[i].color.r, vertices[i].color.g, vertices[i].color.b, vertices[i].color.a);
    CCRenderBufferSetVertex(buffer, i, CCVertexApplyTransform(vertex, &projection));
	}
	
	for (unsigned int i = 0; i < count/3; i++) {
    CCRenderBufferSetTriangle(buffer, i, i*3, (i*3)+1, (i*3)+2);
	}
	
	for (unsigned int i = 0; i < [line->circlesPoints count] / 2;   ++i) {
    LinePoint *prevPoint = [line->circlesPoints objectAtIndex:i * 2];
    LinePoint *curPoint = [line->circlesPoints objectAtIndex:i * 2 + 1];
    CGPoint dirVector = ccpNormalize(ccpSub(curPoint.pos, prevPoint.pos));

    [self fillLineEndPointAt:curPoint.pos direction:dirVector radius:curPoint.width * 0.5f andColor:color forLine:line];
  }
  [line->circlesPoints removeAllObjects];
}

- (NSMutableArray *)calculateSmoothLinePointsForLine:(Line*)line
{
  if (line->points && [line->points count] > 2) {
    NSMutableArray *smoothedPoints = [NSMutableArray array];
    for (unsigned int i = 2; i < [line->points count]; ++i) {
      LinePoint *prev2 = [line->points objectAtIndex:i - 2];
      LinePoint *prev1 = [line->points objectAtIndex:i - 1];
      LinePoint *cur = [line->points objectAtIndex:i];

      CGPoint midPoint1 = ccpMult(ccpAdd(prev1.pos, prev2.pos), 0.5f);
      CGPoint midPoint2 = ccpMult(ccpAdd(cur.pos, prev1.pos), 0.5f);

      int segmentDistance = 2;
      float distance = ccpDistance(midPoint1, midPoint2);
      int numberOfSegments = MIN(128, MAX(floorf(distance / segmentDistance), 32));

      float t = 0.0f;
      float step = 1.0f / numberOfSegments;
      for (NSUInteger j = 0; j < numberOfSegments; j++) {
        LinePoint *newPoint = [[LinePoint alloc] init];
        newPoint.pos = ccpAdd(ccpAdd(ccpMult(midPoint1, powf(1 - t, 2)), ccpMult(prev1.pos, 2.0f * (1 - t) * t)), ccpMult(midPoint2, t * t));
        newPoint.width = powf(1 - t, 2) * ((prev1.width + prev2.width) * 0.5f) + 2.0f * (1 - t) * t * prev1.width + t * t * ((cur.width + prev1.width) * 0.5f);

        [smoothedPoints addObject:newPoint];
        t += step;
      }
      LinePoint *finalPoint = [[LinePoint alloc] init];
      finalPoint.pos = midPoint2;
      finalPoint.width = (cur.width + prev1.width) * 0.5f;
      [smoothedPoints addObject:finalPoint];
    }
    //! we need to leave last 2 points for next draw
    [line->points removeObjectsInRange:NSMakeRange(0, [line->points count] - 2)];
    return smoothedPoints;
  } else {
    return nil;
  }
}

- (void)draw:(CCRenderer *)renderer transform:(const GLKMatrix4 *)transform
{
  ccColor4F color = {0, 0, 0, 1};
  [renderTexture begin];
	
	for (Line* line in [lines objectEnumerator]) {
		NSMutableArray *smoothedPoints = [self calculateSmoothLinePointsForLine:line];
		if (smoothedPoints) {
			[self drawLines:smoothedPoints withColor:color forLine:line];
		}
	}
  [renderTexture end];
}

#pragma mark - Math

#pragma mark - GestureRecognizers

- (float)extractSize:(UITouch *)touch forLine:(Line*)line
{
  //! result of trial & error
	CGPoint prevPoint = line->prevPoint;
	NSTimeInterval prevTime = line->prevTime;
	line->prevPoint = [touch locationInView:touch.view];
	NSTimeInterval timeDiff = touch.timestamp - prevTime;
	line->prevTime = touch.timestamp;
	float vel;
	if (timeDiff > 0) {
		vel = ccpDistance(prevPoint, line->prevPoint) / (timeDiff);
	} else {
		vel = 0;
	}
  float size = vel / 166.0f;
  size = clampf(size, 1, 40);
  if ([line->velocities count] > 1) {
    size = size * 0.2f + [[line->velocities objectAtIndex:[line->velocities count] - 1] floatValue] * 0.8f;
  }
  [line->velocities addObject:[NSNumber numberWithFloat:size]];
  return size;
}

#if 0
- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer
{
  const CGPoint point = [[CCDirector sharedDirector] convertToGL:[panGestureRecognizer locationInView:panGestureRecognizer.view]];

  if (panGestureRecognizer.state == UIGestureRecognizerStateBegan) {
    [points removeAllObjects];
    [velocities removeAllObjects];

    float size = [self extractSize:panGestureRecognizer];

    [self startNewLineFrom:point withSize:size];
    [self addPoint:point withSize:size];
    [self addPoint:point withSize:size];
  }

  if (panGestureRecognizer.state == UIGestureRecognizerStateChanged) {
    //! skip points that are too close
    float eps = 1.5f;
    if ([points count] > 0) {
      float length = ccpLength(ccpSub([(LinePoint *)[points lastObject] pos], point));

      if (length < eps) {
        return;
      } else {
      }
    }
    float size = [self extractSize:panGestureRecognizer];
    [self addPoint:point withSize:size];
  }

  if (panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
    float size = [self extractSize:panGestureRecognizer];
    [self endLineAt:point withSize:size];
  }
}
#endif

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPressGestureRecognizer
{
  [renderTexture beginWithClear:1.0 g:1.0 b:1.0 a:0];
  [renderTexture end];
}
@end
