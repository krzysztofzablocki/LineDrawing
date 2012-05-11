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
#import "CCNode+SFGestureRecognizers.h"

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

@interface LineDrawer ()

- (void)fillLineTriangles:(LineVertex *)vertices count:(NSUInteger)count withColor:(ccColor4F)color;

- (void)startNewLineFrom:(CGPoint)newPoint withSize:(CGFloat)aSize;

- (void)endLineAt:(CGPoint)aEndPoint withSize:(CGFloat)aSize;

- (void)addPoint:(CGPoint)newPoint withSize:(CGFloat)size;

- (void)drawLines:(NSArray *)linePoints withColor:(ccColor4F)color;

@end

@implementation LineDrawer {
  NSMutableArray *points;
  NSMutableArray *velocities;
  NSMutableArray *circlesPoints;

  BOOL connectingLine;
  CGPoint prevC, prevD;
  CGPoint prevG;
  CGPoint prevI;
  float overdraw;

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

    shaderProgram_ = [[CCShaderCache sharedShaderCache] programForKey:kCCShader_PositionColor];
    overdraw = 3.0f;

    renderTexture = [[CCRenderTexture alloc] initWithWidth:(int)self.contentSize.width height:(int)self.contentSize.height pixelFormat:kCCTexture2DPixelFormat_RGBA8888];
    renderTexture.anchorPoint = ccp(0, 0);
    renderTexture.position = ccp(1024 * 0.5f, 768 * 0.5f);
    [renderTexture clear:1.0f g:1.0f b:1.0f a:0];
    [self addChild:renderTexture];

    self.isTouchEnabled = YES;

    UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    panGestureRecognizer.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:panGestureRecognizer];

    UILongPressGestureRecognizer *longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self addGestureRecognizer:longPressGestureRecognizer];
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

- (void)drawLines:(NSArray *)linePoints withColor:(ccColor4F)color
{
  unsigned int numberOfVertices = ([linePoints count] - 1) * 18;
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
    if (connectingLine || index > 0) {
      A = prevC;
      B = prevD;
    } else if (index == 0) {
      //! circle at start of line, revert direction
      [circlesPoints addObject:pointValue];
      [circlesPoints addObject:[linePoints objectAtIndex:i - 1]];
    }

    ADD_TRIANGLE(A, B, C, 1.0f);
    ADD_TRIANGLE(B, C, D, 1.0f);

    prevD = D;
    prevC = C;
    if (finishingLine && (i == [linePoints count] - 1)) {
      [circlesPoints addObject:[linePoints objectAtIndex:i - 1]];
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

    ADD_TRIANGLE(F, A, G, 2.0f);
    ADD_TRIANGLE(A, G, C, 2.0f);
    ADD_TRIANGLE(B, H, D, 2.0f);
    ADD_TRIANGLE(H, D, I, 2.0f);
  }
  [self fillLineTriangles:vertices count:index withColor:color];

  if (index > 0) {
    connectingLine = YES;
  }

  free(vertices);
}

- (void)fillLineEndPointAt:(CGPoint)center direction:(CGPoint)aLineDir radius:(CGFloat)radius andColor:(ccColor4F)color
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
    vertices[i * 9 + 3].pos = ccpAdd(prevPoint, ccpMult(prevDir, overdraw));
    vertices[i * 9 + 3].color.a = 0;
    vertices[i * 9 + 4].pos = prevPoint;
    vertices[i * 9 + 5].pos = ccpAdd(curPoint, ccpMult(dir, overdraw));
    vertices[i * 9 + 5].color.a = 0;

    vertices[i * 9 + 6].pos = prevPoint;
    vertices[i * 9 + 7].pos = curPoint;
    vertices[i * 9 + 8].pos = ccpAdd(curPoint, ccpMult(dir, overdraw));
    vertices[i * 9 + 8].color.a = 0;

    prevPoint = curPoint;
    prevDir = dir;
    angle += anglePerSegment;
  }

  glVertexAttribPointer(kCCVertexAttrib_Position, 3, GL_FLOAT, GL_FALSE, sizeof(LineVertex), &vertices[0].pos);
  glVertexAttribPointer(kCCVertexAttrib_Color, 4, GL_FLOAT, GL_FALSE, sizeof(LineVertex), &vertices[0].color);
  glDrawArrays(GL_TRIANGLES, 0, numberOfSegments * 9);

  free(vertices);
}

- (void)fillLineTriangles:(LineVertex *)vertices count:(NSUInteger)count withColor:(ccColor4F)color
{
  [shaderProgram_ use];
  [shaderProgram_ setUniformForModelViewProjectionMatrix];

  ccGLEnableVertexAttribs(kCCVertexAttribFlag_Position | kCCVertexAttribFlag_Color);

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

  glVertexAttribPointer(kCCVertexAttrib_Position, 3, GL_FLOAT, GL_FALSE, sizeof(LineVertex), &vertices[0].pos);
  glVertexAttribPointer(kCCVertexAttrib_Color, 4, GL_FLOAT, GL_FALSE, sizeof(LineVertex), &vertices[0].color);


  glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  glDrawArrays(GL_TRIANGLES, 0, (GLsizei)count);

  for (unsigned int i = 0; i < [circlesPoints count] / 2; ++i) {
    LinePoint *prevPoint = [circlesPoints objectAtIndex:i * 2];
    LinePoint *curPoint = [circlesPoints objectAtIndex:i * 2 + 1];
    CGPoint dirVector = ccpNormalize(ccpSub(curPoint.pos, prevPoint.pos));

    [self fillLineEndPointAt:curPoint.pos direction:dirVector radius:curPoint.width * 0.5f andColor:color];
  }
  [circlesPoints removeAllObjects];
}

- (NSMutableArray *)calculateSmoothLinePoints
{
  if ([points count] > 2) {
    NSMutableArray *smoothedPoints = [NSMutableArray array];
    for (unsigned int i = 2; i < [points count]; ++i) {
      LinePoint *prev2 = [points objectAtIndex:i - 2];
      LinePoint *prev1 = [points objectAtIndex:i - 1];
      LinePoint *cur = [points objectAtIndex:i];

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
    [points removeObjectsInRange:NSMakeRange(0, [points count] - 2)];
    return smoothedPoints;
  } else {
    return nil;
  }
}

- (void)draw
{
  ccColor4F color = {0, 0, 0, 1};
  [renderTexture begin];

  NSMutableArray *smoothedPoints = [self calculateSmoothLinePoints];
  if (smoothedPoints) {
    [self drawLines:smoothedPoints withColor:color];
  }
  [renderTexture end];
}

#pragma mark - Math

#pragma mark - GestureRecognizers

- (float)extractSize:(UIPanGestureRecognizer *)panGestureRecognizer
{
  //! result of trial & error
  float vel = ccpLength([panGestureRecognizer velocityInView:panGestureRecognizer.view]);
  float size = vel / 166.0f;
  size = clampf(size, 1, 40);

  if ([velocities count] > 1) {
    size = size * 0.2f + [[velocities objectAtIndex:[velocities count] - 1] floatValue] * 0.8f;
  }
  [velocities addObject:[NSNumber numberWithFloat:size]];
  return size;
}

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

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPressGestureRecognizer
{
  [renderTexture beginWithClear:1.0 g:1.0 b:1.0 a:0];
  [renderTexture end];
}
@end