/* -*- c-style: gnu -*-

   Copyright (c) 2013 John Harper <jsh@unfactored.org>

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation files
   (the "Software"), to deal in the Software without restriction,
   including without limitation the rights to use, copy, modify, merge,
   publish, distribute, sublicense, and/or sell copies of the Software,
   and to permit persons to whom the Software is furnished to do so,
   subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. */

#import <Foundation/Foundation.h>

extern CFStringRef PDTypeRAWImage;	/* public.camera-raw-image */
extern CFStringRef PDTypePhodMetadata;	/* org.unfactored.phod-metadata */

extern NSString *const PDImagePropertyDidChange;

@protocol PDImageHost;
@class PDImageLibrary;

enum PDImageCompareKey
{
  PDImageCompare_FileName,
  PDImageCompare_FileDate,
  PDImageCompare_FileSize,
  PDImageCompare_Name,
  PDImageCompare_Date,
  PDImageCompare_Keywords,
  PDImageCompare_Caption,
  PDImageCompare_Rating,
  PDImageCompare_Flagged,
  PDImageCompare_Orientation,
  PDImageCompare_PixelSize,
  PDImageCompare_Altitude,
  PDImageCompare_ExposureLength,
  PDImageCompare_FNumber,
  PDImageCompare_ISOSpeed,
};

typedef int PDImageCompareKey;

@interface PDImage : NSObject <NSPasteboardWriting>
{
  PDImageLibrary *_library;
  NSString *_libraryDirectory;		/* relative to _libraryRoot */

  NSString *_jsonFile;			/* may be nil */

  BOOL _pendingJSONWrite;

  CFStringRef _jpegType;
  NSString *_jpegFile;			/* non-nil iff _jpegType non-nil */
  uint32_t _jpegId;

  CFStringRef _rawType;
  NSString *_rawFile;			/* non-nil iff _rawType non-nil */
  uint32_t _rawId;

  NSMutableDictionary *_properties;
  NSDictionary *_implicitProperties;	/* from the image file(s) */

  NSMapTable *_imageHosts;

  BOOL _donePrefetch;
  NSOperation *_prefetchOp;

  NSDate *_date;			/* cached lazily */

  NSUUID *_uuid;			/* cached eagerly */
  int _rating;
  BOOL _deleted;
  BOOL _hidden;

  BOOL _invalidated;			/* set by -remove */
}

+ (void)callWithImageComparator:(PDImageCompareKey)key
    reversed:(BOOL)flag block:(void (^)(NSComparator))block;

+ (NSString *)imageCompareKeyString:(PDImageCompareKey)key;
+ (PDImageCompareKey)imageCompareKeyFromString:(NSString *)str;

- (id)initWithLibrary:(PDImageLibrary *)lib directory:(NSString *)dir
    JSONFile:(NSString *)json_file;

- (id)initWithLibrary:(PDImageLibrary *)lib directory:(NSString *)dir
    properties:(NSDictionary *)dict;

@property(nonatomic, readonly) PDImageLibrary *library;

@property(nonatomic, readonly) NSString *libraryDirectory;

/* Allocates a new persistent identifier when first called. */

- (NSUUID *)UUID;
- (NSUUID *)UUIDIfDefined;

/* File names relative to 'libraryDirectory'. */

@property(nonatomic, readonly) NSString *JSONFile;
@property(nonatomic, readonly) NSString *JPEGFile;
@property(nonatomic, readonly) NSString *RAWFile;

/* Absolute paths. */

@property(nonatomic, readonly) NSString *JPEGPath;
@property(nonatomic, readonly) NSString *RAWPath;

/* Convenience for titles. */

@property(nonatomic, readonly) NSString *lastLibraryPathComponent;

/* Convience for ActiveType and FileTypes properties. */

@property(nonatomic) BOOL usesRAW;

- (BOOL)supportsUsesRAW:(BOOL)flag;

/* These automatically switch between JPEG and RAW files. */

@property(nonatomic, readonly) NSString *imageFile;
@property(nonatomic, readonly) NSString *imagePath;
@property(nonatomic, readonly) uint32_t imageFileId;

- (id)imagePropertyForKey:(NSString *)key;
- (void)setImageProperty:(id)obj forKey:(NSString *)key;

+ (BOOL)imagePropertyIsEditableInUI:(NSString *)key;

/* Converting image properties to displayable forms. */

+ (NSString *)localizedNameOfImageProperty:(NSString *)key;

- (NSString *)localizedImagePropertyForKey:(NSString *)key;
- (void)setLocalizedImageProperty:(id)obj forKey:(NSString *)key;

/* For use with NSExpression/NSPredicate -- a KVC'able object whose
   keys look up the formatted image properties. */

- (id)expressionValues;

/* Access to the properties that aren't stored in the image's metadata,
   or that override that storage. */

- (NSDictionary *)explicitProperties;

/* Convenience accessors for misc image properties. */

@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *caption;
@property(nonatomic) unsigned int orientation;

@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic, getter=isDeleted) BOOL deleted;
@property(nonatomic, getter=isFlagged) BOOL flagged;
@property(nonatomic) int rating;

@property(nonatomic, readonly) NSDate *date;
@property(nonatomic, readonly) CGSize pixelSize;
@property(nonatomic, readonly) CGSize orientedPixelSize;

/* Delete all traces of the image from the filesystem. */

- (NSError *)remove;

/* Move within the library, self is updated to reflect the new
   location. */

- (BOOL)moveToDirectory:(NSString *)dir error:(NSError **)err;

/* Copy to anywhere. */

- (BOOL)copyToDirectoryPath:(NSString *)path resetUUID:(BOOL)flag
    error:(NSError **)err;

/* Fill proxy caches asynchronously. */

- (void)startPrefetching;
- (void)stopPrefetching;
- (BOOL)isPrefetching;

- (void)addImageHost:(id<PDImageHost>)obj;
- (void)removeImageHost:(id<PDImageHost>)obj;
- (void)updateImageHost:(id<PDImageHost>)obj;

@end

@protocol PDImageHost <NSObject>

- (NSDictionary *)imageHostOptions;

/* Note: may be called more than once, first with low-quality, then
   with high-quality image. */

- (void)image:(PDImage *)im setHostedImage:(CGImageRef)im;

@optional

/* Queue that -setHostedImage: should be invoked from. If not defined,
   the main queue is used. */

- (dispatch_queue_t)imageHostQueue;

@end

/* Image properties. */

extern NSString * const PDImage_Name;		// NSString
extern NSString * const PDImage_UUID;		// NSString
extern NSString * const PDImage_ActiveType;	// NSString
extern NSString * const PDImage_FileTypes;	// NSDictionary (image-type -> image-file)
extern NSString * const PDImage_PixelWidth;	// NSNumber
extern NSString * const PDImage_PixelHeight;	// NSNumber
extern NSString * const PDImage_Orientation;	// NSNumber
extern NSString * const PDImage_ColorModel;	// NSString
extern NSString * const PDImage_ProfileName;	// NSString

extern NSString * const PDImage_Title;		// NSString
extern NSString * const PDImage_Caption;	// NSString
extern NSString * const PDImage_Keywords;	// NSArray
extern NSString * const PDImage_Copyright;	// NSString
extern NSString * const PDImage_Rating;		// NSNumber -1..5
extern NSString * const PDImage_Flagged;	// NSNumber<bool>
extern NSString * const PDImage_Hidden;		// NSNumber<bool>
extern NSString * const PDImage_Deleted;	// NSNumber<bool>

extern NSString * const PDImage_Altitude;	// NSNumber (metres)
extern NSString * const PDImage_CameraMake;	// NSString
extern NSString * const PDImage_CameraModel;	// NSString
extern NSString * const PDImage_CameraSoftware;	// NSString
extern NSString * const PDImage_Contrast;	// NSNumber
extern NSString * const PDImage_DigitizedDate;	// NSNumber
extern NSString * const PDImage_Direction;	// NSNumber (degrees)
extern NSString * const PDImage_DirectionRef;	// NSString: "M", "T" (Magnetic, True north)
extern NSString * const PDImage_ExposureBias;	// NSNumber
extern NSString * const PDImage_ExposureLength;	// NSNumber
extern NSString * const PDImage_ExposureMode;	// NSNumber
extern NSString * const PDImage_ExposureProgram; // NSNumber
extern NSString * const PDImage_Flash;		// NSNumber
extern NSString * const PDImage_FlashCompensation; // NSNumber
extern NSString * const PDImage_FNumber;	// NSNumber
extern NSString * const PDImage_FocalLength;	// NSNumber
extern NSString * const PDImage_FocalLength35mm; // NSNumber
extern NSString * const PDImage_FocusMode;	// NSNumber
extern NSString * const PDImage_ISOSpeed;	// NSNumber
extern NSString * const PDImage_ImageStabilization; // NSNumber
extern NSString * const PDImage_Latitude;	// NSNumber (degrees)
extern NSString * const PDImage_LightSource;	// NSNumber
extern NSString * const PDImage_Longitude;	// NSNumber (degrees)
extern NSString * const PDImage_MaxAperture;	// NSNumber
extern NSString * const PDImage_MeteringMode;	// NSNumber
extern NSString * const PDImage_OriginalDate;	// NSNumber
extern NSString * const PDImage_Saturation;	// NSNumber
extern NSString * const PDImage_SceneCaptureType; // NSNumber
extern NSString * const PDImage_SceneType;	// NSNumber
extern NSString * const PDImage_SensitivityType; // NSNumber
extern NSString * const PDImage_Sharpness;	// NSNumber
extern NSString * const PDImage_WhiteBalance;	// NSNumber

/* Read-only implicit properties. */

extern NSString * const PDImage_Date;		// NSNumber
extern NSString * const PDImage_FileName;	// NSString
extern NSString * const PDImage_FilePath;	// NSString
extern NSString * const PDImage_FileDate;	// NSNumber
extern NSString * const PDImage_FileSize;	// NSNumber
extern NSString * const PDImage_Rejected;	// NSNumber<bool>

/* Hosted image options. */

extern NSString * const PDImageHost_Size;	// NSValue<Size>
extern NSString * const PDImageHost_Thumbnail;	// NSNumber<bool>
extern NSString * const PDImageHost_ColorSpace;	// only a hint
extern NSString * const PDImageHost_NoPreview;	// NSNumber<bool>
