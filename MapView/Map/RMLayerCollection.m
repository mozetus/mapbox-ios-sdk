//
//  RMLayerSet.m
//
// Copyright (c) 2008-2009, Route-Me Contributors
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "RMLayerCollection.h"
#import "RMMapContents.h"
#import "RMMercatorToScreenProjection.h"
#import "RMMarker.h"

@implementation RMLayerCollection

- (id)initForContents:(RMMapContents *)contents
{
    if (!(self = [super init]))
        return nil;

    sublayers = [[NSMutableArray alloc] init];
    mapContents = contents;
    self.masksToBounds = YES;
    rotationTransform = CGAffineTransformIdentity;

    return self;
}

- (void)dealloc
{
    [sublayers release]; sublayers = nil;
    mapContents = nil;
    [super dealloc];
}

- (BOOL)isLayer:(CALayer *)layer withinBounds:(CGRect)bounds
{
    CGPoint markerPosition = layer.position;

    if (![layer isKindOfClass:[RMMarker class]])
        return YES;

    if (markerPosition.x > bounds.origin.x
        && markerPosition.x < bounds.origin.x + bounds.size.width
        && markerPosition.y > bounds.origin.y
        && markerPosition.y < bounds.origin.y + bounds.size.height)
    {
        return YES;
    }

    return NO;
}

- (BOOL)isLayerOnScreen:(CALayer *)layer
{
    CGRect screenBounds = [[mapContents mercatorToScreenProjection] screenBounds];
    return [self isLayer:layer withinBounds:screenBounds];
}

- (void)correctScreenPosition:(CALayer *)layer
{
    if ([layer conformsToProtocol:@protocol(RMMovingMapLayer)])
    {
        // Kinda ugly.
        if (((CALayer <RMMovingMapLayer> *)layer).enableDragging)
        {
            RMProjectedPoint location = [((CALayer <RMMovingMapLayer> *)layer) projectedLocation];
            CGPoint markerPosition = [[mapContents mercatorToScreenProjection] projectProjectedPoint:location];
            layer.position = markerPosition;
        }
        if (!((CALayer <RMMovingMapLayer> *)layer).enableRotation) {
            [((CALayer <RMMovingMapLayer> *)layer) setAffineTransform:rotationTransform];
        }
    }
}

- (void)setSublayers:(NSArray *)array
{
    @synchronized(sublayers) {
        [sublayers removeAllObjects];
        [sublayers addObjectsFromArray:array];

        for (CALayer *layer in array)
        {
            [self correctScreenPosition:layer];
            if ([self isLayerOnScreen:layer])
                [super addSublayer:layer];
        }
    }
}

- (void)addSublayer:(CALayer *)layer
{
    @synchronized(sublayers) {
        [self correctScreenPosition:layer];
        [sublayers addObject:layer];
        if ([self isLayerOnScreen:layer])
            [super addSublayer:layer];
    }
}

- (void)removeSublayer:(CALayer *)layer
{
    @synchronized(sublayers) {
        [sublayers removeObject:layer];
        [layer removeFromSuperlayer];
    }
}

- (void)removeSublayers:(NSArray *)layers
{
    @synchronized(sublayers) {
        for (CALayer *aLayer in layers)
        {
            [sublayers removeObject:aLayer];
            [aLayer removeFromSuperlayer];
        }
    }
}

- (void)insertSublayer:(CALayer *)layer above:(CALayer *)siblingLayer
{
    @synchronized(sublayers) {
        [self correctScreenPosition:layer];
        NSUInteger index = [sublayers indexOfObject:siblingLayer];
        [sublayers insertObject:layer atIndex:index + 1];
        if ([self isLayerOnScreen:layer])
            [super insertSublayer:layer above:siblingLayer];
    }
}

- (void)insertSublayer:(CALayer *)layer below:(CALayer *)siblingLayer
{
    @synchronized(sublayers) {
        [self correctScreenPosition:layer];
        NSUInteger index = [sublayers indexOfObject:siblingLayer];
        [sublayers insertObject:layer atIndex:index];
        if ([self isLayerOnScreen:layer])
            [super insertSublayer:layer below:siblingLayer];
    }
}

- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned)index
{
    @synchronized(sublayers) {
        [self correctScreenPosition:layer];
        [sublayers insertObject:layer atIndex:index];
        if ([self isLayerOnScreen:layer])
            [super insertSublayer:layer atIndex:index];
    }
}

- (void)moveToProjectedPoint:(RMProjectedPoint)aPoint
{
    /// \bug TODO: Test this. Does it work?
    [self correctPositionOfAllSublayers];
}

- (void)moveBy:(CGSize)delta
{
    @synchronized(sublayers) {
        for (id layer in sublayers)
        {
            if ([layer respondsToSelector:@selector(moveBy:)])
                [layer moveBy:delta];

            // if layer moves on and offscreen...
        }
    }
}

- (void)zoomByFactor:(float)zoomFactor near:(CGPoint)center
{
    @synchronized(sublayers) {
        for (id layer in sublayers)
        {
            if ([layer respondsToSelector:@selector(zoomByFactor:near:)])
                [layer zoomByFactor:zoomFactor near:center];
        }
    }
}

- (void)correctPositionOfAllSublayers
{
    [self correctPositionOfAllSublayersIncludingInvisibleLayers:YES];
}

- (void)correctPositionOfAllSublayersIncludingInvisibleLayers:(BOOL)correctAllLayers
{
    @synchronized(sublayers) {
        CGRect screenBounds = [[mapContents mercatorToScreenProjection] screenBounds];
        CALayer *lastLayer = nil;

        if (correctAllLayers) {
            for (id layer in sublayers)
            {
                [self correctScreenPosition:layer];
                if ([self isLayer:layer withinBounds:screenBounds]) {
                    if (![[self sublayers] containsObject:layer]) {
                        if (!lastLayer)
                            [super insertSublayer:layer atIndex:0];
                        else
                            [super insertSublayer:layer above:lastLayer];
                    }
                } else {
                    [layer removeFromSuperlayer];
                }
                lastLayer = layer;
            }
//            RMLog(@"%d layers on screen", [[self sublayers] count]);

        } else {
            for (id layer in [self sublayers])
            {
                [self correctScreenPosition:layer];
            }
//            RMLog(@"updated %d layers on screen", [[self sublayers] count]);
        }
    }
}

- (BOOL)hasSubLayer:(CALayer *)layer
{
    return [sublayers containsObject:layer];
}

- (void)setRotationOfAllSublayers:(float)angle
{
    rotationTransform = CGAffineTransformMakeRotation(angle); // store rotation transform for subsequent layers

    @synchronized(sublayers) {
        for (id layer in sublayers)
        {
            CALayer <RMMovingMapLayer> *mapLayer = (CALayer <RMMovingMapLayer> *)layer;
            if (!mapLayer.enableRotation) {
                [mapLayer setAffineTransform:rotationTransform];
            }
        }
    }
}

@end
