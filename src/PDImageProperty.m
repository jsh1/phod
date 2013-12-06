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

CA_HIDDEN @interface PDImageExpressionObject : NSObject
{
@public
  PDImage *_image;
}
@end

static time_t PDImageParseEXIFDateString_(NSString *str);

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
	  kCGImagePropertyExifSensitivityType,
	  kCGImagePropertyExifSharpness,
	  kCGImagePropertyExifWhiteBalance,
 	};
      const void *exif_values[] =
	{
	  PDImage_Contrast,
	  kCFNull,			/* DigitizedDate */
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
	  kCFNull,			/* OriginalDate */
	  PDImage_Saturation,
	  PDImage_SceneCaptureType,
	  PDImage_SceneType,
	  PDImage_SensitivityType,
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
      else if ((CFEqual(key, kCGImagePropertyExifDateTimeDigitized)
		|| CFEqual(key, kCGImagePropertyExifDateTimeOriginal))
	       && CFGetTypeID(value) == CFStringGetTypeID())
	{
	  time_t date = PDImageParseEXIFDateString_((NSString *)value);
	  if (date != 0)
	    {
	      NSString *k = CFEqual(key, kCGImagePropertyExifDateTimeDigitized)
			    ? PDImage_DigitizedDate : PDImage_OriginalDate;
	      [c->dict setObject:
	       [NSNumber numberWithUnsignedLong:date] forKey:k];
	    }
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
  type_sensitivity_type,
  type_sharpness,
  type_string,
  type_string_array,
  type_unix_date,
  type_white_balance,
} property_type;

typedef struct {
  const char *name;
  property_type type;
} type_pair;

static const type_pair type_map[] =
{
  {"active_type", type_string},
  {"altitude", type_metres},
  {"camera_make", type_string},
  {"camera_model", type_string},
  {"camera_software", type_string},
  {"caption", type_string},
  {"color_model", type_string},
  {"contrast", type_contrast},
  {"copyright", type_string},
  {"digitized_date", type_unix_date},
  {"direction", type_direction},
  {"direction_ref", type_string},
  {"exposure_bias", type_exposure_bias},
  {"exposure_length", type_duration},
  {"exposure_mode", type_exposure_mode},
  {"exposure_program", type_exposure_program},
  {"f_number", type_fstop},
  {"file_date", type_unix_date},
  {"file_size", type_bytes},
  {"file_types", type_string_array},
  {"flagged", type_bool},
  {"flash", type_flash_mode},
  {"flash_compensation", type_flash_compensation},
  {"focal_length", type_millimetres},
  {"focal_length_35mm", type_millimetres},
  {"focus_mode", type_focus_mode},
  {"hidden", type_bool},
  {"iso_speed", type_iso_speed},
  {"image_stabilization", type_image_stabilization_mode},
  {"keywords", type_string_array},
  {"latitude", type_latitude},
  {"light_source", type_light_source},
  {"longitude", type_longitude},
  {"max_aperture", type_fstop},		/* fixme: "APEX" aperture? */
  {"metering_mode", type_metering_mode},
  {"name", type_string},
  {"orientation", type_orientation},
  {"original_date", type_unix_date},
  {"pixel_height", type_pixels},
  {"pixel_width", type_pixels},
  {"profile_name", type_string},
  {"rating", type_rating},
  {"rejected", type_bool},
  {"saturation", type_saturation},
  {"scene_capture_type", type_scene_capture_type},
  {"scene_type", type_scene_type},
  {"sensitivity_type", type_sensitivity_type},
  {"sharpness", type_sharpness},
  {"title", type_string},
  {"white_balance", type_white_balance},
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

static const NSString *flash_modes[] = {
  [0x00] = @"Flash did not fire",
  [0x01] = @"Flash fired",
  [0x05] = @"Strobe return light not detected",
  [0x07] = @"Strobe return light detected",
  [0x09] = @"Flash fired, compulsory flash mode",
  [0x0d] = @"Flash fired, compulsory flash mode, return light not detected",
  [0x0f] = @"Flash fired, compulsory flash mode, return light detected",
  [0x10] = @"Flash did not fire, compulsory flash mode",
  [0x18] = @"Flash did not fire, auto mode",
  [0x19] = @"Flash fired, auto mode",
  [0x1d] = @"Flash fired, auto mode, return light not detected",
  [0x1f] = @"Flash fired, auto mode, return light detected",
  [0x20] = @"No flash function",
  [0x41] = @"Flash fired, red-eye reduction mode",
  [0x45] = @"Flash fired, red-eye reduction mode, return light not detected",
  [0x47] = @"Flash fired, red-eye reduction mode, return light detected",
  [0x49] = @"Flash fired, compulsory flash mode, red-eye reduction mode",
  [0x4d] = @"Flash fired, compulsory flash mode, red-eye reduction mode, return light not detected",
  [0x4f] = @"Flash fired, compulsory flash mode, red-eye reduction mode, return light detected",
  [0x59] = @"Flash fired, auto mode, red-eye reduction mode",
  [0x5d] = @"Flash fired, auto mode, return light not detected, red-eye reduction mode",
  [0x5f] = @"Flash fired, auto mode, return light detected, red-eye reduction mode",
};

static const NSString *contrast[] = {@"Normal", @"Low", @"High"};

static const NSString *exposure_mode[] = {@"Auto Exposure",
  @"Manual Exposure", @"Auto Exposure Bracket"};

static const NSString *white_balance[] = {@"Auto White Balance",
  @"Manual White Balance"};

static const NSString *exposure_prog[] = {@"Unknown Program", @"Manual",
  @"Normal Program", @"Aperture Priority", @"Shutter Priority",
  @"Creative Program", @"Action Program", @"Portrait Mode",
  @"Landscape Mode", @"Bulb Mode"};

static const NSString *metering_mode[] = {nil, @"Average",
  @"Center-Weighted Average", @"Spot", @"Multi-Spot", @"Pattern",
  @"Partial"};

static const NSString *orientation_type[] = {nil, @"Landscape",
  @"Mirror Horizontal", @"Rotate 180", @"Mirror Vertical",
  @"Mirror Horizontal and Rotate 270 CW",
  @"Rotate 90 CW", @"Mirror Horizontal and Rotate 90 CW",
  @"Rotate 270 CW"};

static const NSString *light_sources[] = {nil, @"Daylight",
  @"Fluorescent", @"Tungsten (Incandescent)", @"Flash", nil, nil, nil, nil,
  @"Fine Weather", @"Cloudy", @"Shade", @"Daylight Fluorescent",
  @"Day White Fluorescent", @"Cool White Fluorescent",
  @"White Fluorescent", @"Warm White Fluorescent", @"Standard Light A",
  @"Standard Light B", @"Standard Light C", @"D55", @"D65", @"D75",
  @"D50", @"ISO Studio Tungsten"};

static const NSString *scene_types[] = {nil, @"Directly Photographed"};

static const NSString *scene_capture_types[] = {@"Standard", @"Landscape",
  @"Portrait", @"Night"};

static const NSString *sensitivity_types[] = {nil,
  @"Standard Output Sensitivity", @"Recommended Exposure Index",
  @"ISO Speed", @"Standard Output Sensitivity and Recommended Exposure Index",
  @"Standard Output Sensitivity and ISO Speed",
  @"Recommended Exposure Index and ISO Speed",
  @"Standard Output Sensitivity, Recommended Exposure Index and ISO Speed"};

static inline NSString *
array_lookup(int idx, NSString **array, size_t nelts)
{
  NSString *str = idx >= 0 && idx < nelts ? array[idx] : nil;
  return str != nil ? str : @"Unknown";
}

static NSString *
lookup_enum_string(property_type type, int idx)
{
  switch (type)
    {
    case type_contrast:
      return array_lookup(idx, contrast, N_ELEMENTS(contrast));
	
    case type_exposure_mode:
      return array_lookup(idx, exposure_mode, N_ELEMENTS(exposure_mode));

    case type_exposure_program:
      return array_lookup(idx, exposure_prog, N_ELEMENTS(exposure_prog));

    case type_flash_mode:
      return array_lookup(idx, flash_modes, N_ELEMENTS(flash_modes));

    case type_light_source:
      return array_lookup(idx, light_sources, N_ELEMENTS(light_sources));
      
    case type_scene_type:
      return array_lookup(idx, scene_types, N_ELEMENTS(scene_types));

    case type_scene_capture_type:
      return array_lookup(idx, scene_capture_types,
			  N_ELEMENTS(scene_capture_types));

    case type_sensitivity_type:
      return array_lookup(idx, sensitivity_types,
			  N_ELEMENTS(sensitivity_types));

    case type_metering_mode:
      return array_lookup(idx, metering_mode, N_ELEMENTS(metering_mode));

    case type_orientation:
      return array_lookup(idx, orientation_type, N_ELEMENTS(orientation_type));

    case type_white_balance:
      return array_lookup(idx, white_balance, N_ELEMENTS(white_balance));

    case type_focus_mode:
    case type_image_stabilization_mode:
      /* FIXME: definitions? */

    default:
      return nil;
    }
}

NSString *
PDImageLocalizedNameOfProperty(NSString *key)
{
  return [[NSBundle mainBundle] localizedStringForKey:key
	  value:key table:@"image-properties"];
}

NSString *
PDImageLocalizedPropertyValue(NSString *key, id value, PDImage *im)
{
  property_type type = lookup_property_type([key UTF8String]);

  switch (type)
    {
      double x;
      const char *str;
      NSDate *date;

    case type_bool:
      return [value intValue] != 0 ? @"True" : @"False";

    case type_bytes:
      x = [value doubleValue];
      if (x > 1024.*1024.*1024.*1024.)
	x = x / (1024.*1024.*1024.*1024.), str = "TB";
      else if (x > 1024.*1024.*1024.)
	x = x / (1024.*1024.*1024.), str = "GB";
      else if (x > 1024*1024)
	x = x / (1024*1024), str = "MB";
      else if (x > 1024)
	x = x / 1024, str = "KB";
      else
	str ="bytes";
      return [NSString stringWithFormat:@"%.3g %s", x, str];
      
    case type_duration:
      if ([value doubleValue] < 1)
	return [NSString stringWithFormat:@"1/%g", 1/[value doubleValue]];
      else
	return [NSString stringWithFormat:@"%g", [value doubleValue]];

    case type_latitude:
      x = [value doubleValue];
      return [NSString stringWithFormat:@"%g%@ %s",
	      fabs(x), degrees_string(), x >= 0 ? "North" : "South"];

    case type_longitude:
      x = [value doubleValue];
      return [NSString stringWithFormat:@"%g%@ %s",
	      fabs(x), degrees_string(), x >= 0 ? "East" : "West"];

    case type_metres:
      return [NSString stringWithFormat:@"%gm", [value doubleValue]];

    case type_millimetres:
      return [NSString stringWithFormat:@"%gmm", [value doubleValue]];

    case type_direction:
      str = ![[im imagePropertyForKey:PDImage_DirectionRef]
	      isEqual:@"T"] ? "Magnetic North" : "True North";
      return [NSString stringWithFormat:@"%g%@ %s",
	      [value doubleValue], degrees_string(), str];

    case type_exposure_bias:
      return [NSString stringWithFormat:@"%.2g ev", [value doubleValue]];

    case type_fstop:
      return [NSString stringWithFormat:@"f/%g", [value doubleValue]];

    case type_iso_speed:
      return [NSString stringWithFormat:@"ISO %g", [value doubleValue]];

    case type_contrast:
    case type_exposure_mode:
    case type_exposure_program:
    case type_flash_mode:
    case type_metering_mode:
    case type_white_balance:
    case type_image_stabilization_mode:
    case type_scene_type:
    case type_scene_capture_type:
    case type_sensitivity_type:
    case type_focus_mode:
    case type_light_source:
    case type_orientation:
      return lookup_enum_string(type, [value intValue]);

    case type_unix_date:
      date = [NSDate dateWithTimeIntervalSince1970:
	      [value unsignedLongValue]];
      if (date != nil)
	{
	  static NSDateFormatter *formatter;
	  static dispatch_once_t once;

	  dispatch_once(&once, ^{
	    formatter = [[NSDateFormatter alloc] init];
	    [formatter setDateStyle:NSDateFormatterMediumStyle];
	    [formatter setTimeStyle:NSDateFormatterMediumStyle];
	  });

	  return [formatter stringFromDate:date];
	}
      break;

    case type_string:
      return value;

    case type_string_array:
      return [(NSArray *)value componentsJoinedByString:@" "];

    case type_flash_compensation:
    case type_pixels:
    case type_rating:
    case type_saturation:
    case type_sharpness:
      break;

    case type_unknown:
      break;
    }

  return [NSString stringWithFormat:@"%@", value];
}

id
PDImageUnlocalizedPropertyValue(NSString *key, NSString *str, PDImage *im)
{
  property_type type = lookup_property_type([key UTF8String]);

  switch (type)
    {
    case type_string:
      return str;

    case type_string_array:
      return [str componentsSeparatedByCharactersInSet:
	      [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    case type_bool:
      return [NSNumber numberWithBool:[str boolValue]];

    default:
      break;
    }

  return nil;
}

NSDictionary *
PDImageExpressionValues(PDImage *im)
{
  PDImageExpressionObject *obj
    = [[PDImageExpressionObject alloc] init];
  obj->_image = [im retain];
  return [obj autorelease];
}

@implementation PDImageExpressionObject

- (id)valueForKey:(id)key
{
  id value = [_image imagePropertyForKey:key];

  property_type type = lookup_property_type([key UTF8String]);

  switch (type)
    {
    case type_bool:
      return [NSNumber numberWithBool:[value intValue] != 0];

    case type_unix_date:
      return [NSDate dateWithTimeIntervalSince1970:[value unsignedLongValue]];

    case type_string:
      return value != nil ? value : @"";

    case type_string_array:
      return value != nil ? value : [NSArray array];

    case type_contrast:
    case type_exposure_mode:
    case type_exposure_program:
    case type_flash_mode:
    case type_metering_mode:
    case type_white_balance:
    case type_scene_type:
    case type_scene_capture_type:
    case type_sensitivity_type:
    case type_light_source:
    case type_orientation:
    case type_focus_mode:
    case type_image_stabilization_mode:
      return lookup_enum_string(type, [value intValue]);

    case type_direction:
    case type_exposure_bias:
    case type_fstop:
    case type_duration:
    case type_iso_speed:
    case type_latitude:
    case type_longitude:
    case type_metres:
    case type_millimetres:
    case type_bytes:
    case type_flash_compensation:
    case type_pixels:
    case type_rating:
    case type_saturation:
    case type_sharpness:
      /* Numeric values remain numeric, nil = zero. */
      return value != nil ? value : [NSNumber numberWithInt:0];

    case type_unknown:
      break;
    }

  return nil;
}

@end


/* EXIF date parsing. */

static time_t
PDImageParseEXIFDateString_(NSString *str)
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

      return mktime(&tm);
    }
  else
    return 0;
}

NSDate *
PDImageParseEXIFDateString(NSString *str)
{
  time_t date = PDImageParseEXIFDateString_(str);
  if (date != 0)
    return [NSDate dateWithTimeIntervalSince1970:date];
  else
    return nil;
}


/* NSPredicateEditor templates for image properties. */

static NSPredicateEditorRowTemplate *
predicate_compound_template(void)
{
  NSArray *compound_types = @[@(NSNotPredicateType),
			     @(NSAndPredicateType),
			     @(NSOrPredicateType)];

  return [[[NSPredicateEditorRowTemplate alloc]
	   initWithCompoundTypes:compound_types]
	  autorelease];
}

static NSPredicateEditorRowTemplate *
predicate_string_template(void)
{
  NSMutableArray *string_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_Name, PDImage_ActiveType,
			  PDImage_ColorModel, PDImage_ProfileName,
			  PDImage_Title, PDImage_Caption,
			  PDImage_Copyright, PDImage_CameraMake,
			  PDImage_CameraModel, PDImage_CameraSoftware])
    {
      [string_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *string_ops = @[@(NSEqualToPredicateOperatorType),
			  @(NSNotEqualToPredicateOperatorType),
			  @(NSBeginsWithPredicateOperatorType),
			  @(NSEndsWithPredicateOperatorType),
			  @(NSContainsPredicateOperatorType)];

  return [[[NSPredicateEditorRowTemplate alloc]
	   initWithLeftExpressions:string_keys rightExpressionAttributeType:
	   NSStringAttributeType modifier:NSDirectPredicateModifier
	   operators:string_ops options:NSCaseInsensitivePredicateOption
	   | NSDiacriticInsensitivePredicateOption]
	  autorelease];
}

static NSPredicateEditorRowTemplate *
predicate_numeric_template(void)
{
  NSMutableArray *numeric_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_FileSize, PDImage_PixelWidth,
			  PDImage_PixelHeight, PDImage_Rating,
			  PDImage_Altitude, PDImage_Direction,
			  PDImage_ExposureBias, PDImage_ExposureLength,
			  PDImage_FNumber, PDImage_FocalLength,
			  PDImage_FocalLength35mm, PDImage_ISOSpeed,
			  PDImage_Latitude, PDImage_Longitude,
			  PDImage_MaxAperture, PDImage_Saturation,
			  PDImage_Sharpness])
    {
      [numeric_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *numeric_ops = @[@(NSEqualToPredicateOperatorType),
			   @(NSNotEqualToPredicateOperatorType),
			   @(NSLessThanPredicateOperatorType),
			   @(NSLessThanOrEqualToPredicateOperatorType),
			   @(NSGreaterThanPredicateOperatorType),
			   @(NSGreaterThanOrEqualToPredicateOperatorType)];

  return [[[NSPredicateEditorRowTemplate alloc] initWithLeftExpressions:
	   numeric_keys rightExpressionAttributeType:NSDoubleAttributeType
	   modifier:NSDirectPredicateModifier operators:numeric_ops options:0]
	  autorelease];
}

static NSPredicateEditorRowTemplate *
predicate_bool_template(void)
{
  NSMutableArray *bool_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_Flagged, PDImage_Hidden, PDImage_Rejected])
    {
      [bool_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *bool_values = @[[NSExpression expressionForConstantValue:
			    [NSNumber numberWithBool:NO]],
			   [NSExpression expressionForConstantValue:
			    [NSNumber numberWithBool:YES]]];

  NSArray *bool_ops = @[@(NSEqualToPredicateOperatorType),
			   @(NSNotEqualToPredicateOperatorType)];

  return [[[NSPredicateEditorRowTemplate alloc]
	   initWithLeftExpressions:bool_keys rightExpressions:bool_values
	   modifier:NSDirectPredicateModifier operators:bool_ops options:0]
	  autorelease];
}

static NSPredicateEditorRowTemplate *
predicate_date_template(void)
{
  NSMutableArray *date_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_FileDate, PDImage_OriginalDate,
			  PDImage_DigitizedDate])
    {
      [date_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *date_ops = @[@(NSEqualToPredicateOperatorType),
			@(NSNotEqualToPredicateOperatorType),
			@(NSLessThanPredicateOperatorType),
			@(NSLessThanOrEqualToPredicateOperatorType),
			@(NSGreaterThanPredicateOperatorType),
			@(NSGreaterThanOrEqualToPredicateOperatorType)];

  return [[[NSPredicateEditorRowTemplate alloc]
	   initWithLeftExpressions:date_keys rightExpressionAttributeType:
	   NSDateAttributeType modifier:NSDirectPredicateModifier
	   operators:date_ops options:0]
	  autorelease];
}

static NSPredicateEditorRowTemplate *
predicate_string_array_template(void)
{
  NSMutableArray *array_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_Keywords, PDImage_FileTypes])
    {
      [array_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *string_ops = @[@(NSEqualToPredicateOperatorType),
			  @(NSNotEqualToPredicateOperatorType),
			  @(NSBeginsWithPredicateOperatorType),
			  @(NSEndsWithPredicateOperatorType),
			  @(NSContainsPredicateOperatorType)];

  return [[[NSPredicateEditorRowTemplate alloc]
	   initWithLeftExpressions:array_keys rightExpressionAttributeType:
	   NSStringAttributeType modifier:NSAnyPredicateModifier
	   operators:string_ops options:0]
	  autorelease];
}

static NSPredicateEditorRowTemplate *
predicate_enum_template(NSString *key, NSString **array, size_t nelts)
{
  NSExpression *enum_key = [NSExpression expressionForKeyPath:key];

  NSMutableArray *enum_values = [NSMutableArray array];

  size_t i;
  for (i = 0; i < nelts; i++)
    {
      if (array[i] == nil)
	continue;
      [enum_values addObject:
       [NSExpression expressionForConstantValue:array[i]]];
    }

  NSArray *enum_ops = @[@(NSEqualToPredicateOperatorType),
			@(NSNotEqualToPredicateOperatorType)];

  return [[[NSPredicateEditorRowTemplate alloc]
	   initWithLeftExpressions:@[enum_key] rightExpressions:enum_values
	   modifier:NSDirectPredicateModifier operators:enum_ops options:0]
	  autorelease];
}

#define ENUM(x, y) predicate_enum_template(PDImage_##x, y, N_ELEMENTS(y))

NSArray *
PDImagePredicateEditorRowTemplates(void)
{
  static NSArray *templates;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    templates = @[
      predicate_compound_template(),
      predicate_string_template(),
      predicate_numeric_template(),
      predicate_bool_template(),
      predicate_date_template(),
      predicate_string_array_template(),
      ENUM(Contrast, contrast),
      ENUM(ExposureMode, exposure_mode),
      ENUM(ExposureProgram, exposure_prog),
      ENUM(Flash, flash_modes),
      ENUM(LightSource, light_sources),
      ENUM(SceneType, scene_types),
      ENUM(SceneCaptureType, scene_capture_types),
      ENUM(SensitivityType, sensitivity_types),
      ENUM(MeteringMode, metering_mode),
      ENUM(Orientation, orientation_type),
      ENUM(WhiteBalance, white_balance)
    ];
    [templates retain];
  });

  return templates;
}

#undef ENUM


/* Property string definitions. */

NSString * const PDImage_Name = @"name";
NSString * const PDImage_ActiveType = @"active_type";
NSString * const PDImage_FileTypes = @"file_types";
NSString * const PDImage_PixelWidth = @"pixel_width";
NSString * const PDImage_PixelHeight = @"pixel_height";
NSString * const PDImage_Orientation = @"orientation";
NSString * const PDImage_ColorModel = @"color_model";
NSString * const PDImage_ProfileName = @"profile_name";

NSString * const PDImage_Title = @"title";
NSString * const PDImage_Caption = @"caption";
NSString * const PDImage_Keywords = @"keywords";
NSString * const PDImage_Copyright = @"copyright";
NSString * const PDImage_Rating = @"rating";
NSString * const PDImage_Flagged = @"flagged";
NSString * const PDImage_Hidden = @"hidden";

NSString * const PDImage_Altitude = @"altitude";
NSString * const PDImage_Aperture = @"aperture";
NSString * const PDImage_CameraMake = @"camera_make";
NSString * const PDImage_CameraModel = @"camera_model";
NSString * const PDImage_CameraSoftware = @"camera_software";
NSString * const PDImage_Contrast = @"contrast";
NSString * const PDImage_DigitizedDate = @"digitized_date";
NSString * const PDImage_Direction = @"direction";
NSString * const PDImage_DirectionRef = @"direction_ref";
NSString * const PDImage_ExposureBias = @"exposure_bias";
NSString * const PDImage_ExposureLength = @"exposure_length";
NSString * const PDImage_ExposureMode = @"exposure_mode";
NSString * const PDImage_ExposureProgram = @"exposure_program";
NSString * const PDImage_Flash = @"flash";
NSString * const PDImage_FlashCompensation = @"flash_compensation";
NSString * const PDImage_FNumber = @"f_number";
NSString * const PDImage_FocalLength = @"focal_length";
NSString * const PDImage_FocalLength35mm = @"focal_length_35mm";
NSString * const PDImage_FocusMode = @"focus_mode";
NSString * const PDImage_ISOSpeed = @"iso_speed";
NSString * const PDImage_ImageStabilization = @"image_stabilization";
NSString * const PDImage_Latitude = @"latitude";
NSString * const PDImage_LightSource = @"light_source";
NSString * const PDImage_Longitude = @"longitude";
NSString * const PDImage_MaxAperture = @"max_aperture";
NSString * const PDImage_MeteringMode = @"metering_mode";
NSString * const PDImage_OriginalDate = @"original_date";
NSString * const PDImage_Saturation = @"saturation";
NSString * const PDImage_SceneCaptureType = @"scene_capture_type";
NSString * const PDImage_SceneType = @"scene_type";
NSString * const PDImage_SensitivityType = @"sensitivity_type";
NSString * const PDImage_Sharpness = @"sharpness";
NSString * const PDImage_WhiteBalance = @"white_balance";

NSString * const PDImage_FileName = @"file_name";
NSString * const PDImage_FilePath = @"file_path";
NSString * const PDImage_FileDate = @"file_date";
NSString * const PDImage_FileSize = @"file_size";
NSString * const PDImage_Rejected = @"rejected";
