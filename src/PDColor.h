// -*- c-style: gnu -*-

#import <AppKit/NSColor.h>

@interface PDColor : NSColor

+ (NSColor *)windowBackgroundColor;

+ (NSColor *)controlTextColor;
+ (NSColor *)disabledControlTextColor;
+ (NSColor *)controlTextColor:(BOOL)disabled;

+ (NSColor *)controlDetailTextColor;
+ (NSColor *)disabledControlDetailTextColor;
+ (NSColor *)controlDetailTextColor:(BOOL)disabled;

+ (NSColor *)controlBackgroundColor;
+ (NSColor *)darkControlBackgroundColor;
+ (NSArray *)controlAlternatingRowBackgroundColors;

@end
