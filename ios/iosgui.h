/* iOS/UIKit GUI type definitions for Emacs.
   Copyright (C) 2025 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

#ifndef EMACS_IOSGUI_H
#define EMACS_IOSGUI_H

/* This gets included from both Objective-C and plain C files.  */
#ifdef __OBJC__

#ifdef Z
#warning "Z is defined. If you get a later parse error in a header, check that buffer.h or other files #define-ing Z are not included."
#endif

#define Cursor IOSCursorDummy
#import <UIKit/UIKit.h>
#undef Cursor

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

#include <AvailabilityMacros.h>
#include <TargetConditionals.h>

#endif /* __OBJC__ */

/* Emulate XCharStruct - same as NS port.  */
typedef struct _XCharStruct
{
  int rbearing;
  int lbearing;
  int width;
  int ascent;
  int descent;
} XCharStruct;

/* Pixmap type - use CGImage on iOS.  */
#ifdef __OBJC__
typedef id Emacs_Pixmap;
#else
typedef void *Emacs_Pixmap;
#endif

/* Cursor type - iOS doesn't have system cursors like macOS,
   but we keep the type for API compatibility.  */
#ifdef __OBJC__
typedef id Emacs_Cursor;
#else
typedef void *Emacs_Cursor;
#endif

/* Window handle - just an integer on iOS.  */
typedef int Window;

/* CGFloat and geometry types for non-ObjC code.  */
#ifndef __OBJC__
#if defined (__LP64__) && __LP64__
typedef double CGFloat;
#else
typedef float CGFloat;
#endif
typedef struct _CGPoint { CGFloat x, y; } CGPoint;
typedef struct _CGSize  { CGFloat width, height; } CGSize;
typedef struct _CGRect  { CGPoint origin; CGSize size; } CGRect;
#endif  /* NOT OBJC */

/* iOS uses CGRect as the native rectangle type.  */
#define NativeRectangle CGRect

#define CONVERT_TO_EMACS_RECT(xr, nr)		\
  ((xr).x     = (nr).origin.x,			\
   (xr).y     = (nr).origin.y,			\
   (xr).width = (nr).size.width,		\
   (xr).height = (nr).size.height)

#define CONVERT_FROM_EMACS_RECT(xr, nr)		\
  ((nr).origin.x    = (xr).x,			\
   (nr).origin.y    = (xr).y,			\
   (nr).size.width  = (xr).width,		\
   (nr).size.height = (xr).height)

#define STORE_NATIVE_RECT(nr, px, py, pwidth, pheight)	\
  ((nr).origin.x    = (px),			\
   (nr).origin.y    = (py),			\
   (nr).size.width  = (pwidth),			\
   (nr).size.height = (pheight))

/* RGB pixel color - same as NS port.  */
typedef unsigned long RGB_PIXEL_COLOR;

/* Helper macro to convert RGB to unsigned long.  */
#define RGB_TO_ULONG(r, g, b) (((r) << 16) | ((g) << 8) | (b))
#define ARGB_TO_ULONG(a, r, g, b) (((a) << 24) | ((r) << 16) | ((g) << 8) | (b))
#define RED_FROM_ULONG(color) (((color) >> 16) & 0xff)
#define GREEN_FROM_ULONG(color) (((color) >> 8) & 0xff)
#define BLUE_FROM_ULONG(color) ((color) & 0xff)
#define RED16_FROM_ULONG(color) (RED_FROM_ULONG(color) * 0x101)
#define GREEN16_FROM_ULONG(color) (GREEN_FROM_ULONG(color) * 0x101)
#define BLUE16_FROM_ULONG(color) (BLUE_FROM_ULONG(color) * 0x101)


/* Gravity constants needed by frame.c.  */
#define ForgetGravity		0
#define NorthWestGravity	1
#define NorthGravity		2
#define NorthEastGravity	3
#define WestGravity		4
#define CenterGravity		5
#define EastGravity		6
#define SouthWestGravity	7
#define SouthGravity		8
#define SouthEastGravity	9
#define StaticGravity		10

#define NoValue		0x0000
#define XValue  	0x0001
#define YValue		0x0002
#define WidthValue  	0x0004
#define HeightValue  	0x0008
#define AllValues 	0x000F
#define XNegative 	0x0010
#define YNegative 	0x0020

#define USPosition	(1L << 0) /* user specified x, y */
#define USSize		(1L << 1) /* user specified width, height */

#define PPosition	(1L << 2) /* program specified position */
#define PSize		(1L << 3) /* program specified size */
#define PMinSize	(1L << 4) /* program specified minimum size */
#define PMaxSize	(1L << 5) /* program specified maximum size */
#define PResizeInc	(1L << 6) /* program specified resize increments */
#define PAspect		(1L << 7) /* program specified min, max aspect ratios */
#define PBaseSize	(1L << 8) /* program specified base for incrementing */
#define PWinGravity	(1L << 9) /* program specified window gravity */

/* iOS-specific event types (used by both C and ObjC sources).  */
enum ios_event_type
  {
    IOS_TOUCH_BEGIN,
    IOS_TOUCH_MOVE,
    IOS_TOUCH_END,
    IOS_TOUCH_CANCEL,
    IOS_KEY_DOWN,
    IOS_KEY_UP,
    IOS_FOCUS_IN,
    IOS_FOCUS_OUT,
    IOS_CONFIGURE_NOTIFY,
    IOS_EXPOSE,
    IOS_APP_FOREGROUND,
    IOS_APP_BACKGROUND,
    IOS_KEYBOARD_SHOW,
    IOS_KEYBOARD_HIDE,
    IOS_SAFE_AREA_CHANGE,
  };

/* iOS modifier key masks (used by both C and ObjC sources).  */
enum ios_modifier_mask
  {
    IOS_SHIFT_MASK   = (1 << 0),
    IOS_CONTROL_MASK = (1 << 1),
    IOS_OPTION_MASK  = (1 << 2),  /* Meta */
    IOS_COMMAND_MASK = (1 << 3),  /* Super */
    IOS_CAPS_MASK    = (1 << 4),
  };

#endif /* EMACS_IOSGUI_H */
