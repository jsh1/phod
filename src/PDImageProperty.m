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

#import "PDImageProperty.h"

#import <time.h>

#define N_ELEMENTS(x) (sizeof(x) / sizeof((x)[0]))

/* Converting ImageIO properties dictionary to our format. */

static CFDictionaryRef
property_map(void)
{
  static CFDictionaryRef map;
  
  if (map == NULL)
    {
      const void *tiff_keys[] =
	{
	  kCGImagePropertyTIFFMake,
	  kCGImagePropertyTIFFModel,
	  kCGImagePropertyTIFFSoftware,
	};
      const void *tiff_values[] =
	{
	  PDImage_CameraMake,
	  PDImage_CameraModel,
	  PDImage_CameraSoftware,
	};

      const void *exif_keys[] =
	{
	  kCGImagePropertyExifContrast,
	  kCGImagePropertyExifDateTimeDigitized,
	  kCGImagePropertyExifExposureBiasValue,
	  kCGImagePropertyExifExposureTime,
	  kCGImagePropertyExifExposureMode,
	  kCGImagePropertyExifExposureProgram,
	  kCGImagePropertyExifFlash,
	  kCGImagePropertyExifFNumber,
	  kCGImagePropertyExifFocalLength,
	  kCGImagePropertyExifFocalLenIn35mmFilm,
	  kCGImagePropertyExifISOSpeed,
	  kCGImagePropertyExifISOSpeedRatings,
	  kCGImagePropertyExifLightSource,
	  kCGImagePropertyExifMaxApertureValue,
	  kCGImagePropertyExifMeteringMode,
	  kCGImagePropertyExifDateTimeOriginal,
	  kCGImagePropertyExifSaturation,
	  kCGImagePropertyExifSceneCaptureType,
	  kCGImagePropertyExifSceneType,
	  kCGImagePropertyExifSharpness,
	  kCGImagePropertyExifWhiteBalance,
 	};
      const void *exif_values[] =
	{
	  PDImage_Contrast,
	  PDImage_DigitizedDate,
	  PDImage_ExposureBias,
	  PDImage_ExposureLength,
	  PDImage_ExposureMode,
	  PDImage_ExposureProgram,
	  PDImage_Flash,
	  PDImage_FNumber,
	  PDImage_FocalLength,
	  PDImage_FocalLength35mm,
	  PDImage_ISOSpeed,
	  kCFNull,			/* ISOSpeedRatings */
	  PDImage_LightSource,
	  PDImage_MaxAperture,
	  PDImage_MeteringMode,
	  PDImage_OriginalDate,
	  PDImage_Saturation,
	  PDImage_SceneCaptureType,
	  PDImage_SceneType,
	  PDImage_Sharpness,
	  PDImage_WhiteBalance,
	};

      const void *exif_aux_keys[] =
	{
	  kCGImagePropertyExifAuxFlashCompensation,
	  CFSTR("ImageStabilization"),
	};
      const void *exif_aux_values[] =
	{
	  PDImage_FlashCompensation,
	  PDImage_ImageStabilization,
	};

      const void *iptc_keys[] =
	{
	  kCGImagePropertyIPTCKeywords,
	  kCGImagePropertyIPTCStarRating,
 	};
      const void *iptc_values[] =
	{
	  PDImage_Keywords,
	  PDImage_Rating,
	};

      CFDictionaryRef tiff_map = CFDictionaryCreate(NULL, tiff_keys,
	tiff_values, sizeof(tiff_keys) / sizeof(tiff_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
      CFDictionaryRef exif_map = CFDictionaryCreate(NULL, exif_keys,
	exif_values, sizeof(exif_keys) / sizeof(exif_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
      CFDictionaryRef exif_aux_map = CFDictionaryCreate(NULL, exif_aux_keys,
	exif_aux_values, sizeof(exif_aux_keys) / sizeof(exif_aux_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
      CFDictionaryRef iptc_map = CFDictionaryCreate(NULL, iptc_keys,
	iptc_values, sizeof(iptc_keys) / sizeof(iptc_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

      const void *keys[] =
	{
	  kCGImagePropertyFileSize,
	  kCGImagePropertyPixelWidth,
	  kCGImagePropertyPixelHeight,
	  kCGImagePropertyOrientation,
	  kCGImagePropertyColorModel,
	  kCGImagePropertyProfileName,
	  kCGImagePropertyTIFFDictionary,
	  kCGImagePropertyExifDictionary,
	  kCGImagePropertyExifAuxDictionary,
	  kCGImagePropertyIPTCDictionary,
	  kCGImagePropertyGPSDictionary,
	};
      const void *values[] =
	{
	  PDImage_FileSize,
	  PDImage_PixelWidth,
	  PDImage_PixelHeight,
	  PDImage_Orientation,
	  PDImage_ColorModel,
	  PDImage_ProfileName,
	  tiff_map,
	  exif_map,
	  exif_aux_map,
	  iptc_map,
	  kCFNull,
	};
      
      map = CFDictionaryCreate(NULL, keys, values, sizeof(keys) / sizeof(keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

      CFRelease(tiff_map);
      CFRelease(exif_map);
      CFRelease(exif_aux_map);
      CFRelease(iptc_map);
    }

  return map;
}

struct map_closure
{
  CFDictionaryRef map;
  NSMutableDictionary *dict;
};

static void
process_gps_dictionary(CFDictionaryRef gps_dict, NSMutableDictionary *dict)
{
  double value;
  CFTypeRef ptr;
  CFTypeID number_type = CFNumberGetTypeID();

  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLatitude);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      CFNumberGetValue(ptr, kCFNumberDoubleType, &value);
      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLatitudeRef);
      if (ptr != NULL && CFEqual(ptr, CFSTR("S")))
	value = -value;
      id obj = [NSNumber numberWithDouble:value];
      [dict setObject:obj forKey:PDImage_Latitude];
    }
      
  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLongitude);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      CFNumberGetValue(ptr, kCFNumberDoubleType, &value);
      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLongitudeRef);
      if (ptr != NULL && CFEqual(ptr, CFSTR("W")))
	value = -value;
      id obj = [NSNumber numberWithDouble:value];
      [dict setObject:obj forKey:PDImage_Longitude];
    }

  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSAltitude);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      CFNumberGetValue(ptr, kCFNumberDoubleType, &value);
      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSAltitudeRef);
      if (ptr != NULL && CFGetTypeID(ptr) == number_type)
	{
	  int x;
	  CFNumberGetValue(ptr, kCFNumberIntType, &x);
	  if (x == 1)
	    value = -value;
	}
      id obj = [NSNumber numberWithDouble:value];
      [dict setObject:obj forKey:PDImage_Altitude];
    }

  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSImgDirection);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      [dict setObject:(id)ptr forKey:PDImage_Direction];

      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSImgDirectionRef);
      if (ptr != NULL)
	[dict setObject:(id)ptr forKey:PDImage_DirectionRef];
    }
}

static void
map_property(const void *key, const void *value, void *ctx)
{
  struct map_closure *c = ctx;

  const void *mapped_key = CFDictionaryGetValue(c->map, key);

  if (mapped_key == NULL)
    return;

  if (CFGetTypeID(mapped_key) == CFDictionaryGetTypeID()
      && CFGetTypeID(value) == CFDictionaryGetTypeID())
    {
      struct map_closure cc;

      cc.map = mapped_key;
      cc.dict = c->dict;

      CFDictionaryApplyFunction((CFDictionaryRef)value, map_property, &cc);
    }
  else if (mapped_key == kCFNull)
    {
      /* Manual fix-ups. */

      if (CFEqual(key, kCGImagePropertyExifISOSpeedRatings)
	  && CFGetTypeID(value) == CFArrayGetTypeID()
	  && CFArrayGetCount(value) >= 1
	  && [c->dict objectForKey:PDImage_ISOSpeed] == nil)
	{
	  [c->dict setObject:CFArrayGetValueAtIndex(value, 0)
	   forKey:PDImage_ISOSpeed];
	}
      else if (CFEqual(key, kCGImagePropertyGPSDictionary)
	       && CFGetTypeID(value) == CFDictionaryGetTypeID())
	{
	  process_gps_dictionary((CFDictionaryRef)value, c->dict);
	}
      else
	abort();
    }
  else
    {
      [c->dict setObject:(id)value forKey:(id)mapped_key];
    }
}

NSDictionary *
PDImageSourceCopyProperties(CGImageSourceRef src)
{
  CFDictionaryRef dict = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
  if (dict == NULL)
    return [[NSDictionary alloc] init];

  struct map_closure c;

  c.map = property_map();
  c.dict = [[NSMutableDictionary alloc] init];

  CFDictionaryApplyFunction(dict, map_property, &c);

  CFRelease(dict);

  return c.dict;
}


/* Converting properties and their names to localized/displayable forms. */

typedef enum
{
  type_unknown,
  type_bool,
  type_bytes,
  type_contrast,
  type_date,
  type_direction,
  type_duration,
  type_exposure_bias,
  type_exposure_mode,
  type_exposure_program,
  type_focus_mode,
  type_flash_compensation,
  type_flash_mode,
  type_fstop,
  type_image_stabilization_mode,
  type_iso_speed,
  type_latitude,
  type_light_source,
  type_longitude,
  type_metering_mode,
  type_metres,
  type_millimetres,
  type_orientation,
  type_pixels,
  type_rating,
  type_saturation,
  type_scene_capture_type,
  type_scene_type,
  type_sharpness,
  type_string,
  type_string_array,
  type_white_balance,
} property_type;

typedef struct {
  const char *name;
  property_type type;
} type_pair;

static const type_pair type_map[] =
{
  {"ActiveType", type_string},
  {"Altitude", type_metres},
  {"CameraMake", type_string},
  {"CameraModel", type_string},
  {"CameraSoftware", type_string},
  {"Caption", type_string},
  {"ColorModel", type_string},
  {"Contrast", type_contrast},
  {"Copyright", type_string},
  {"DigitizedDate", type_date},
  {"Direction", type_direction},
  {"DirectionRef", type_string},
  {"ExposureBias", type_exposure_bias},
  {"ExposureLength", type_duration},
  {"ExposureMode", type_exposure_mode},
  {"ExposureProgram", type_exposure_program},
  {"FNumber", type_fstop},
  {"FileSize", type_bytes},
  {"FileTypes", type_string_array},
  {"Flagged", type_bool},
  {"Flash", type_flash_mode},
  {"FlashCompensation", type_flash_compensation},
  {"FocalLength", type_millimetres},
  {"FocalLength35mm", type_millimetres},
  {"FocusMode", type_focus_mode},
  {"ISOSpeed", type_iso_speed},
  {"ImageStabilization", type_image_stabilization_mode},
  {"Keywords", type_string_array},
  {"Latitude", type_latitude},
  {"LightSource", type_light_source},
  {"Longitude", type_longitude},
  {"MaxAperture", type_fstop},		/* fixme: "APEX" aperture? */
  {"MeteringMode", type_metering_mode},
  {"Name", type_string},
  {"Orientation", type_orientation},
  {"OriginalDate", type_date},
  {"PixelHeight", type_pixels},
  {"PixelWidth", type_pixels},
  {"ProfileName", type_string},
  {"Rating", type_rating},
  {"Saturation", type_saturation},
  {"SceneCaptureType", type_scene_capture_type},
  {"SceneType", type_scene_type},
  {"Sharpness", type_sharpness},
  {"Title", type_string},
  {"WhiteBalance", type_white_balance},
};

static inline property_type
lookup_property_type(const char *name)
{
  const type_pair *ptr
    = bsearch_b(name, type_map, N_ELEMENTS(type_map), sizeof(type_map[0]),
		^(const void *a, const void *b) {
		  return strcmp(a, *(const char **)b);
		});

  return ptr != NULL ? ptr->type : type_unknown;
}

static inline NSString *
array_lookup(id value, NSString **array, size_t nelts)
{
  size_t i = [value unsignedIntValue];
  return i < nelts ? array[i] : @"Unknown";
}

static NSString *
degrees_string(void)
{
  static NSString *deg;

  if (deg == nil)
    {
      unichar c = 0x00b0;		/* DEGREE SIGN */
      deg = [[NSString alloc] initWithCharacters:&c length:1];
    }

  return deg;
}

static NSString *
exif_flash_mode(unsigned int x)
{
  switch (x)
    {
    case 0x00:
      return @"Flash did not fire";
    case 0x01:
      return @"Flash fired";
    case 0x05:
      return @"Strobe return light not detected";
    case 0x07:
      return @"Strobe return light detected";
    case 0x09:
      return @"Flash fired, compulsory flash mode";
    case 0x0d:
      return @"Flash fired, compulsory flash mode, return light not detected";
    case 0x0f:
      return @"Flash fired, compulsory flash mode, return light detected";
    case 0x10:
      return @"Flash did not fire, compulsory flash mode";
    case 0x18:
      return @"Flash did not fire, auto mode";
    case 0x19:
      return @"Flash fired, auto mode";
    case 0x1d:
      return @"Flash fired, auto mode, return light not detected";
    case 0x1f:
      return @"Flash fired, auto mode, return light detected";
    case 0x20:
      return @"No flash function";
    case 0x41:
      return @"Flash fired, red-eye reduction mode";
    case 0x45:
      return @"Flash fired, red-eye reduction mode, return light not detected";
    case 0x47:
      return @"Flash fired, red-eye reduction mode, return light detected";
    case 0x49:
      return @"Flash fired, compulsory flash mode, red-eye reduction mode";
    case 0x4d:
      return @"Flash fired, compulsory flash mode, red-eye reduction mode, return light not detected";
    case 0x4f:
      return @"Flash fired, compulsory flash mode, red-eye reduction mode, return light detected";
    case 0x59:
      return @"Flash fired, auto mode, red-eye reduction mode";
    case 0x5d:
      return @"Flash fired, auto mode, return light not detected, red-eye reduction mode";
    case 0x5f:
      return @"Flash fired, auto mode, return light detected, red-eye reduction mode}";
    default:
      return @"Unknown flash mode.";
    }
}

static const NSString *contrast[] = {@"Normal", @"Low", @"High"};
static const NSString *exposure_mode[] = {@"Auto Exposure",
  @"Manual Exposure", @"Auto Exposure Bracket"};
static const NSString *white_balance[] = {@"Auto White Balance",
  @"Manual White Balance"};
static const NSString *exposure_prog[] = {@"Unknown Program", @"Manual",
  @"Normal Program", @"Aperture Priority", @"Shutter Priority",
  @"Creative Program", @"Action Program", @"Portrait Mode",
  @"Landscape Mode", @"Bulb Mode"};
static const NSString *metering_mode[] = {@"Unknown", @"Average",
  @"Center-Weighted Average", @"Spot", @"Multi-Spot", @"Pattern",
  @"Partial"};

NSString *
PDImageLocalizedNameOfProperty(NSString *key)
{
  return [[NSBundle mainBundle] localizedStringForKey:key
	  value:key table:@"image-properties"];
}

NSString *
PDImageLocalizedPropertyValue(NSString *key, id value, PDImage *im)
{
  switch (lookup_property_type([key UTF8String]))
    {
      double x;
      const char *str;

    case type_bool:
      return [value boolValue] ? @"True" : @"False";

    case type_contrast:
      return array_lookup(value, contrast, N_ELEMENTS(contrast));
	
    case type_direction:
      str = ![[im imagePropertyForKey:PDImage_DirectionRef]
	      isEqual:@"T"] ? "Magnetic North" : "True North";
      return [NSString stringWithFormat:@"%g%@ %s",
	      [value doubleValue], degrees_string(), str];

    case type_exposure_bias:
      return [NSString stringWithFormat:@"%.2g ev", [value doubleValue]];

    case type_fstop:
      return [NSString stringWithFormat:@"f/%g", [value doubleValue]];

    case type_duration:
      if ([value doubleValue] < 1)
	return [NSString stringWithFormat:@"1/%g", 1/[value doubleValue]];
      else
	return [NSString stringWithFormat:@"%g", [value doubleValue]];

    case type_exposure_mode:
      return array_lookup(value, exposure_mode, N_ELEMENTS(exposure_mode));

    case type_exposure_program:
      return array_lookup(value, exposure_prog, N_ELEMENTS(exposure_prog));

    case type_flash_mode:
      return exif_flash_mode([value unsignedIntValue]);

    case type_iso_speed:
      return [NSString stringWithFormat:@"ISO %g", [value doubleValue]];

    case type_latitude:
      x = [value doubleValue];
      return [NSString stringWithFormat:@"%g%@ %s",
	      fabs(x), degrees_string(), x >= 0 ? "North" : "South"];

    case type_longitude:
      x = [value doubleValue];
      return [NSString stringWithFormat:@"%g%@ %s",
	      fabs(x), degrees_string(), x >= 0 ? "East" : "West"];

    case type_metering_mode:
      return array_lookup(value, metering_mode, N_ELEMENTS(metering_mode));

    case type_metres:
      return [NSString stringWithFormat:@"%gm", [value doubleValue]];

    case type_millimetres:
      return [NSString stringWithFormat:@"%gmm", [value doubleValue]];

    case type_white_balance:
      return array_lookup(value, white_balance, N_ELEMENTS(white_balance));

    case type_bytes:
    case type_date:
    case type_flash_compensation:
    case type_focus_mode:
    case type_image_stabilization_mode:
    case type_light_source:
    case type_orientation:
    case type_pixels:
    case type_rating:
    case type_saturation:
    case type_scene_capture_type:
    case type_scene_type:
    case type_sharpness:
    case type_string:
    case type_string_array:
      break;

    case type_unknown:
      break;
    }

  return [NSString stringWithFormat:@"%@", value];
}


/* EXIF date parsing. */

NSDate *
PDImageParseEXIFDateString(NSString *str)
{
  /* Format is "YYYY:MM:DD HH:MM:SS". */

  int year, month, day;
  int hours, minutes, seconds;

  if (sscanf([str UTF8String], "%d:%d:%d %d:%d:%d",
	     &year, &month, &day, &hours, &minutes, &seconds) == 6)
    {
      struct tm tm = {0};
      tm.tm_year = year - 1900;
      tm.tm_mon = month - 1;
      tm.tm_mday = day;
      tm.tm_hour = hours;
      tm.tm_min = minutes;
      tm.tm_sec = seconds;

      return [NSDate dateWithTimeIntervalSince1970:mktime(&tm)];
    }
  else
    return nil;
}


/* Property string definitions. */

NSString * const PDImage_Name = @"Name";
NSString * const PDImage_ActiveType = @"ActiveType";
NSString * const PDImage_FileTypes = @"FileTypes";
NSString * const PDImage_FileSize = @"FileSize";
NSString * const PDImage_PixelWidth = @"PixelWidth";
NSString * const PDImage_PixelHeight = @"PixelHeight";
NSString * const PDImage_Orientation = @"Orientation";
NSString * const PDImage_ColorModel = @"ColorModel";
NSString * const PDImage_ProfileName = @"ProfileName";

NSString * const PDImage_Title = @"Title";
NSString * const PDImage_Caption = @"Caption";
NSString * const PDImage_Keywords = @"Keywords";
NSString * const PDImage_Copyright = @"Copyright";
NSString * const PDImage_Rating = @"Rating";
NSString * const PDImage_Flagged = @"Flagged";

NSString * const PDImage_Altitude = @"Altitude";
NSString * const PDImage_Aperture = @"Aperture";
NSString * const PDImage_CameraMake = @"CameraMake";
NSString * const PDImage_CameraModel = @"CameraModel";
NSString * const PDImage_CameraSoftware = @"CameraSoftware";
NSString * const PDImage_Contrast = @"Contrast";
NSString * const PDImage_DigitizedDate = @"DigitizedDate";
NSString * const PDImage_Direction = @"Direction";
NSString * const PDImage_DirectionRef = @"DirectionRef";
NSString * const PDImage_ExposureBias = @"ExposureBias";
NSString * const PDImage_ExposureLength = @"ExposureLength";
NSString * const PDImage_ExposureMode = @"ExposureMode";
NSString * const PDImage_ExposureProgram = @"ExposureProgram";
NSString * const PDImage_Flash = @"Flash";
NSString * const PDImage_FlashCompensation = @"FlashCompensation";
NSString * const PDImage_FNumber = @"FNumber";
NSString * const PDImage_FocalLength = @"FocalLength";
NSString * const PDImage_FocalLength35mm = @"FocalLength35mm";
NSString * const PDImage_FocusMode = @"FocusMode";
NSString * const PDImage_ISOSpeed = @"ISOSpeed";
NSString * const PDImage_ImageStabilization = @"ImageStabilization";
NSString * const PDImage_Latitude = @"Latitude";
NSString * const PDImage_LightSource = @"LightSource";
NSString * const PDImage_Longitude = @"Longitude";
NSString * const PDImage_MaxAperture = @"MaxAperture";
NSString * const PDImage_MeteringMode = @"MeteringMode";
NSString * const PDImage_OriginalDate = @"OriginalDate";
NSString * const PDImage_Saturation = @"Saturation";
NSString * const PDImage_SceneCaptureType = @"SceneCaptureType";
NSString * const PDImage_SceneType = @"SceneType";
NSString * const PDImage_Sharpness = @"Sharpness";
NSString * const PDImage_WhiteBalance = @"WhiteBalance";
