/* iOS/UIKit communication module.      -*- coding: utf-8 -*-

Copyright (C) 2025-2026 Free Software Foundation, Inc.

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

/*
iOS/UIKit port by the Emacs community.
Based on the NeXTstep/macOS port.
*/

/* This should be the first include, as it may set up #defines affecting
   interpretation of even the system includes.  */
#include <config.h>

#ifdef HAVE_IOS

#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <sys/types.h>
#include <time.h>
#include <signal.h>
#include <unistd.h>

#include <c-ctype.h>
#include <c-strcase.h>
#include <ftoastr.h>

#include "lisp.h"
#include "blockinput.h"
#include "sysselect.h"
#include "iosterm.h"
#include "systime.h"
#include "character.h"
#include "fontset.h"
#include "composite.h"
#include "ccl.h"

/* Flag to indicate iOS GUI is available.
   Set to true by the iOS app before calling ios_emacs_init().
   Checked in init_display_interactive() to initialize iOS window system.  */
bool ios_init_gui = false;

/* Color map loaded from rgb.txt.  This must be a static variable
   protected by staticpro to avoid being garbage collected.  */
static Lisp_Object Vios_color_map;

#include "termhooks.h"
#include "termchar.h"
#include "menu.h"
#include "window.h"
#include "keyboard.h"
#include "buffer.h"
#include "font.h"
#include "pdumper.h"
#include "dispextern.h"

/* Include macfont for CoreText font support (shared with macOS).  */
#include "macfont.h"

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
/* IOSurface is available on iOS but with limited API.  For now, skip it.  */
/* #import <IOSurface/IOSurface.h> */


/* ==========================================================================

   UIKit Thread Safety Helpers
   
   All UIKit APIs MUST be called on the main thread.  Emacs runs its
   computation on a background thread, so we need helpers to dispatch
   UI operations to the main thread.

   ========================================================================== */

/* Forward declarations.  */
static void ios_clear_frame_area (struct frame *f, int x, int y, int width, int height);

/* Safely request a view to redraw on the main thread.  */
static void
ios_request_display (UIView *view)
{
  if (!view)
    return;
    
  if ([NSThread isMainThread])
    {
      [view setNeedsDisplay];
    }
  else
    {
      dispatch_async (dispatch_get_main_queue (), ^{
        [view setNeedsDisplay];
      });
    }
}

/* Safely request a rect to redraw on the main thread.  */
static void
ios_request_display_rect (UIView *view, CGRect rect)
{
  if (!view)
    return;
    
  if ([NSThread isMainThread])
    {
      [view setNeedsDisplayInRect:rect];
    }
  else
    {
      dispatch_async (dispatch_get_main_queue (), ^{
        [view setNeedsDisplayInRect:rect];
      });
    }
}


/* ==========================================================================

   iOS Path Variables
   
   These are set by ios_init_paths() before Emacs initialization.
   They are used by epaths.h to provide runtime bundle paths.

   ========================================================================== */

/* Directory containing lisp files (e.g., /path/to/Emacs.app/lisp).  */
char *ios_lisp_directory = NULL;

/* Directory containing etc files (e.g., /path/to/Emacs.app/etc).  */
char *ios_etc_directory = NULL;

/* Directory for executables (same as bundle path for iOS).  */
char *ios_exec_directory = NULL;

/* Initialize iOS paths from the bundle.  Called early in startup.  */
void
ios_init_paths (void)
{
  NSLog (@"ios_init_paths: called");
  @autoreleasepool {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundlePath = [bundle bundlePath];
    NSLog (@"ios_init_paths: bundlePath=%@", bundlePath);
    
    /* Lisp directory - from environment or bundle.  */
    const char *emacsloadpath = getenv ("EMACSLOADPATH");
    if (emacsloadpath && *emacsloadpath)
      ios_lisp_directory = strdup (emacsloadpath);
    else
      {
        NSString *lispPath = [bundlePath stringByAppendingPathComponent:@"lisp"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:lispPath])
          ios_lisp_directory = strdup ([lispPath UTF8String]);
      }
    
    /* Etc directory - from environment or bundle.  */
    const char *emacsdata = getenv ("EMACSDATA");
    if (emacsdata && *emacsdata)
      ios_etc_directory = strdup (emacsdata);
    else
      {
        NSString *etcPath = [bundlePath stringByAppendingPathComponent:@"etc"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:etcPath])
          ios_etc_directory = strdup ([etcPath UTF8String]);
      }
    
    /* Exec directory - bundle path.  */
    ios_exec_directory = strdup ([bundlePath UTF8String]);
    
    NSLog (@"ios_init_paths: lisp=%s etc=%s exec=%s",
           ios_lisp_directory ? ios_lisp_directory : "(null)",
           ios_etc_directory ? ios_etc_directory : "(null)",
           ios_exec_directory ? ios_exec_directory : "(null)");
  }
}

/* Override Emacs path variables after syms_of_lread has defined them.
   This is necessary because epaths.h contains hardcoded paths that
   are not valid on iOS.  */
void
ios_override_path_variables (void)
{
  NSLog (@"ios_override_path_variables: FUNCTION ENTRY");
  
  /* Only override if we have valid iOS paths.  */
  if (!ios_lisp_directory)
    {
      NSLog (@"ios_override_path_variables: early return, ios_lisp_directory is NULL");
      return;
    }
    
  /* These are macros defined in globals.h that access globals.f_Vxxx.
     No extern declarations needed.  */
  
  /* Set source-directory to the lisp directory.  */
  Vsource_directory = build_string (ios_lisp_directory);
  
  /* Set data-directory to etc.  */
  if (ios_etc_directory)
    Vdata_directory = build_string (ios_etc_directory);
    
  /* Set doc-directory to etc.  */
  if (ios_etc_directory)
    Vdoc_directory = build_string (ios_etc_directory);
    
  /* Set exec-directory to bundle.  */
  if (ios_exec_directory)
    Vexec_directory = build_string (ios_exec_directory);

  /* Set invocation-directory and invocation-name.
     These are critical for elisp-mode.el macro expansion which uses
     (expand-file-name invocation-name invocation-directory).
     On iOS, argv[0] may not contain a path, leaving these nil.  */
  NSLog (@"[IOS] about to set invocation vars, ios_exec_directory=%s",
         ios_exec_directory ? ios_exec_directory : "(null)");
  if (ios_exec_directory)
    {
      NSLog (@"[IOS] setting Vinvocation_directory to %s", ios_exec_directory);
      Vinvocation_directory = build_string (ios_exec_directory);
      NSLog (@"[IOS] Vinvocation_directory SET successfully");
    }
  else
    {
      NSLog (@"[IOS] WARNING: ios_exec_directory is NULL, cannot set Vinvocation_directory");
    }
  Vinvocation_name = build_string ("Emacs");
  NSLog (@"[IOS] Vinvocation_name SET to Emacs");

  /* On iOS, getcwd() may fail (returning NULL) because iOS apps don't have
     a traditional working directory. This causes default-directory to be nil,
     which breaks file-relative-name during macro expansion (elisp-mode.el).
     Set default-directory to "/" as a safe fallback.  */
  if (NILP (BVAR (current_buffer, directory)))
    {
      NSLog (@"[IOS] default-directory is nil, setting to /");
      bset_directory (current_buffer, build_string ("/"));
    }
  NSLog (@"[IOS] default-directory = %s",
         STRINGP (BVAR (current_buffer, directory))
         ? SSDATA (BVAR (current_buffer, directory)) : "(nil)");

  NSLog (@"ios_override_path_variables: source=%s", SSDATA (Vsource_directory));
  NSLog (@"ios_override_path_variables: DONE - returning to emacs.c");
}

/* Debug log function callable from emacs.c for tracking initialization.  */
void
ios_debug_log (const char *msg)
{
  NSLog (@"[EMACS INIT] %s", msg);
}

/* Get the pdumper fingerprint as a hex string.
   Returns a malloc'd string that the caller must free.
   Used by main.m to find the correct dump file before ios_emacs_init.  */
extern volatile unsigned char fingerprint[];

char *
ios_get_fingerprint (void)
{
  /* Fingerprint is 32 bytes, hex representation is 64 chars + null.  */
  char *hexbuf = malloc (32 * 2 + 1);
  if (!hexbuf)
    return NULL;
  
  for (int i = 0; i < 32; i++)
    sprintf (hexbuf + i * 2, "%02X", fingerprint[i]);
  hexbuf[64] = '\0';
  
  return hexbuf;
}


/* ==========================================================================

   Bootstrap Progress Reporting

   Called during Emacs Lisp loading to update the bootstrap UI.
   These functions are safe to call from the Emacs thread - they
   dispatch UI updates to the main thread internally.
   
   The actual implementations are in BootstrapViewController.m (EmacsApp).
   We provide stub implementations here that will be overridden when
   the app links BootstrapViewController.m.

   ========================================================================== */

/* Stub implementations - these do nothing and will be overridden by
   the actual implementations in BootstrapViewController.m when linked
   into the EmacsApp.  We mark them as weak so the app's strong symbols
   take precedence.  */
__attribute__((weak))
void ios_bootstrap_will_start(void)
{
  /* Stub - does nothing when running temacs directly.  */
}

__attribute__((weak))
void ios_bootstrap_update_progress(float progress __attribute__((unused)),
                                    const char *message __attribute__((unused)))
{
  /* Stub - does nothing when running temacs directly.  */
}

__attribute__((weak))
void ios_bootstrap_update_message(const char *message __attribute__((unused)))
{
  /* Stub - does nothing when running temacs directly.  */
}

__attribute__((weak))
void ios_bootstrap_complete(void)
{
  /* Stub - does nothing when running temacs directly.  */
}

/* Approximate total number of Lisp files loaded during bootstrap.
   This is used to calculate progress percentage.
   Updated empirically - about 85 files are loaded during loadup.el.  */
#define IOS_BOOTSTRAP_TOTAL_FILES 85

/* Current file count for progress tracking.  */
static int ios_bootstrap_file_count = 0;
static bool ios_bootstrap_in_progress = true;

/* Called when pdmp load fails and Emacs will bootstrap from source.
   This notifies the UI to switch from simple loading screen to bootstrap view.  */
void
ios_notify_bootstrap_start (void)
{
  NSLog(@"ios_notify_bootstrap_start: pdmp load failed, switching to bootstrap UI");
  ios_bootstrap_will_start ();
}

/* Called when Emacs starts loading a Lisp file.
   This is hooked from load_with_autoload_queue via ios_load_hook.  */
void
ios_report_load_progress (const char *filename)
{
  static int call_count = 0;
  call_count++;
  
  /* Debug: log ALL calls to see if we're being invoked */
  if (call_count <= 5 || call_count % 20 == 0)
    NSLog(@"ios_report_load_progress[%d]: bootstrap_in_progress=%d file=%s",
          call_count, ios_bootstrap_in_progress, filename ? filename : "(null)");
  
  if (!ios_bootstrap_in_progress)
    return;

  ios_bootstrap_file_count++;
  
  /* Calculate progress (cap at 95% until frame is created).  */
  float progress = (float)ios_bootstrap_file_count / IOS_BOOTSTRAP_TOTAL_FILES;
  if (progress > 0.95f)
    progress = 0.95f;
  
  ios_bootstrap_update_progress (progress, filename);
}

/* Global reference to the main EmacsView for delayed redraw.
   Note: Not using __weak since we're in MRC mode.  The view lifetime
   is managed by the UIWindow hierarchy.  */
static EmacsView *ios_main_emacs_view = nil;
/* Flag to track if bootstrap completed before view was set.
   Used to trigger redraw when view becomes available.  */
static bool ios_bootstrap_complete_pending_redraw = false;
/* Called when bootstrap is complete (frame is about to be shown).  */
void
ios_report_bootstrap_complete (void)
{
  if (!ios_bootstrap_in_progress)
    return;
  ios_bootstrap_complete ();
  NSLog(@"ios_report_bootstrap_complete: checking view availability");
  EmacsView *view = ios_main_emacs_view;
  if (view)
    {
      /* View exists - schedule redraw immediately.  */
      dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"ios_report_bootstrap_complete: view exists, scheduling immediate redraw");
        [view setNeedsDisplay];
      });
    }
  else
    {
      /* View not yet created - set flag so redraw happens when view is set.  */
      NSLog(@"ios_report_bootstrap_complete: view not yet created, setting pending flag");
      ios_bootstrap_complete_pending_redraw = true;
    }
}

/* Set the main EmacsView for delayed redraw.  Called from EmacsView init.
   If bootstrap already completed, triggers the pending redraw.  */
void
ios_set_main_emacs_view (EmacsView *view)
{
  NSLog(@"ios_set_main_emacs_view: view=%p, pending_redraw=%d", view, ios_bootstrap_complete_pending_redraw);
  ios_main_emacs_view = view;
  /* If bootstrap completed before view was ready, trigger redraw now.  */
  if (view && ios_bootstrap_complete_pending_redraw)
    {
      NSLog(@"ios_set_main_emacs_view: triggering pending bootstrap redraw");
      ios_bootstrap_complete_pending_redraw = false;
      dispatch_async(dispatch_get_main_queue(), ^{
        [view setNeedsDisplay];
      });
    }
}


/* ==========================================================================

   IOSTRACE, Trace support.

   ========================================================================== */

#if IOSTRACE_ENABLED

/* The following use "volatile" since they can be accessed from
   parallel threads.  */
volatile int iostrace_num;
volatile int iostrace_depth;

/* When 0, no trace is emitted.  */
volatile int iostrace_enabled_global = 1;

/* Called when iostrace_enabled goes out of scope.  */
void
iostrace_leave (int *pointer_to_iostrace_enabled)
{
  if (*pointer_to_iostrace_enabled)
    --iostrace_depth;
}

/* Called when iostrace_saved_enabled_global goes out of scope.  */
void
iostrace_restore_global_trace_state (int *pointer_to_saved_enabled_global)
{
  iostrace_enabled_global = *pointer_to_saved_enabled_global;
}

#endif /* IOSTRACE_ENABLED */


/* ==========================================================================

   UIColor, EmacsColor category.

   ========================================================================== */

@implementation UIColor (EmacsColor)

+ (UIColor *)colorForEmacsRed:(CGFloat)red green:(CGFloat)green
                         blue:(CGFloat)blue alpha:(CGFloat)alpha
{
  /* iOS always uses sRGB color space.  */
  return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

+ (UIColor *)colorWithUnsignedLong:(unsigned long)c
{
  CGFloat a = (double)((c >> 24) & 0xff) / 255.0;
  CGFloat r = (double)((c >> 16) & 0xff) / 255.0;
  CGFloat g = (double)((c >> 8) & 0xff) / 255.0;
  CGFloat b = (double)(c & 0xff) / 255.0;

  /* If alpha is 0, assume fully opaque (Emacs colors typically don't use alpha).  */
  if (a == 0.0)
    a = 1.0;

  return [UIColor colorForEmacsRed:r green:g blue:b alpha:a];
}

- (unsigned long)unsignedLong
{
  CGFloat r, g, b, a;
  [self getRed:&r green:&g blue:&b alpha:&a];

  return (((unsigned long) (a * 255)) << 24)
    | (((unsigned long) (r * 255)) << 16)
    | (((unsigned long) (g * 255)) << 8)
    | ((unsigned long) (b * 255));
}

@end


/* ==========================================================================

   NSString, EmacsString category.

   ========================================================================== */

@implementation NSString (EmacsString)

+ (NSString *)stringWithLispString:(Lisp_Object)string
{
  /* Convert a Lisp string to an NSString.  */
  return [NSString stringWithUTF8String:SSDATA (string)];
}

- (Lisp_Object)lispString
{
  /* Convert an NSString to a Lisp string.  */
  const char *utf8 = [self UTF8String];
  return build_string (utf8 ? utf8 : "");
}

@end


/* ==========================================================================

   EmacsLayer - CALayer subclass for GPU-accelerated drawing

   ========================================================================== */

@implementation EmacsLayer

+ (id)defaultActionForKey:(NSString *)key
{
  /* Disable implicit animations.  */
  return nil;
}

- (void)display
{
  /* Layer display method - called when the layer needs to render its content.
     The actual drawing happens in the EmacsView's drawRect: method.
     Do NOT call setNeedsDisplay here - that would cause an infinite loop!  */
}

@end


/* ==========================================================================

   EmacsView - Main Emacs rendering view

   ========================================================================== */

@implementation EmacsView

+ (Class)layerClass
{
  /* Use standard CALayer for drawing.  EmacsView's drawRect: will be called.  */
  return [CALayer class];
}

+ (EmacsView *)createFrameView:(struct frame *)f
{
  IOSTRACE ("EmacsView createFrameView");

  if (![NSThread isMainThread])
    {
      __block EmacsView *view = nil;
      dispatch_sync (dispatch_get_main_queue (), ^{
        view = [[EmacsView alloc] initFrameFromEmacsOnMainThread:f];
      });
      return view;
    }

  return [[EmacsView alloc] initFrameFromEmacsOnMainThread:f];
}

- (instancetype)initFrameFromEmacsOnMainThread:(struct frame *)f
{
  IOSTRACE ("EmacsView initFrameFromEmacsOnMainThread");

  /* Calculate initial frame size.  */
  CGRect rect = CGRectMake (0, 0,
                            FRAME_PIXEL_WIDTH (f),
                            FRAME_PIXEL_HEIGHT (f));

  self = [super initWithFrame:rect];
  if (self == nil)
    return nil;

  emacsframe = f;
  FRAME_IOS_VIEW (f) = self;

  windowClosing = NO;
  workingText = nil;
  processingCompose = NO;
  fs_state = 0;
  scrollbarsNeedingUpdate = 0;
  ios_userRect = CGRectMake (0, 0, 0, 0);
  
  /* Initialize offscreen context.  */
  offscreenContext = NULL;
  offscreenData = NULL;
  offscreenWidth = 0;
  offscreenHeight = 0;
  offscreenHasContent = NO;
  backingScaleFactor = [[UIScreen mainScreen] scale];  /* Capture Retina scale */
  pendingResizeWidth = 0;
  pendingResizeHeight = 0;
  
  /* Initialize modifier key state for virtual keyboard.  */
  modCtrl = NO;
  modMeta = NO;
  
  /* Create keyboard accessory view early so it's available when keyboard appears.  */
  [self inputAccessoryView];

  /* Configure for Emacs drawing.  */
  self.backgroundColor = [UIColor blackColor];
  self.opaque = YES;
  self.clearsContextBeforeDrawing = YES;
  self.multipleTouchEnabled = YES;
  self.userInteractionEnabled = YES;  /* CRITICAL for touch events.  */
  self.contentMode = UIViewContentModeRedraw;

  /* Enable layer-backed drawing.  */
  self.layer.drawsAsynchronously = NO;
  self.layer.contentsScale = [[UIScreen mainScreen] scale];

  /* Add gesture recognizers for enhanced touch handling.  */
  [self setupGestureRecognizers];
  
  /* Register for keyboard notifications to handle relayout.  */
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardDidChangeFrame:)
                                               name:UIKeyboardDidChangeFrameNotification
                                             object:nil];
  
  /* Register this view for delayed redraw after bootstrap.  */
  extern void ios_set_main_emacs_view (EmacsView *view);
  ios_set_main_emacs_view (self);

  return self;
}

- (struct frame *)emacsFrame
{
  return emacsframe;
}

- (void)setEmacsFrame:(struct frame *)f
{
  emacsframe = f;
}

- (BOOL)offscreenHasContent
{
  return offscreenHasContent;
}

- (void)setupGestureRecognizers
{
  NSLog(@"setupGestureRecognizers: adding gesture recognizers to view %p", self);
  
  /* Long press for context menu (right-click equivalent).  */
  UILongPressGestureRecognizer *longPress =
    [[UILongPressGestureRecognizer alloc]
      initWithTarget:self action:@selector(handleLongPress:)];
  longPress.minimumPressDuration = 0.5;
  [self addGestureRecognizer:longPress];
  [longPress release];

  /* Double tap for word selection.
     NOTE: Don't release doubleTap until singleTap is configured below,
     because singleTap needs to reference it for requireGestureRecognizerToFail.  */
  UITapGestureRecognizer *doubleTap =
    [[UITapGestureRecognizer alloc]
      initWithTarget:self action:@selector(handleDoubleTap:)];
  doubleTap.numberOfTapsRequired = 2;
  [self addGestureRecognizer:doubleTap];
  /* [doubleTap release]; -- delayed until after singleTap setup */

  /* Triple tap for line selection.  */
  UITapGestureRecognizer *tripleTap =
    [[UITapGestureRecognizer alloc]
      initWithTarget:self action:@selector(handleTripleTap:)];
  tripleTap.numberOfTapsRequired = 3;
  [self addGestureRecognizer:tripleTap];
  [tripleTap release];

  /* Two-finger pan for scrolling.  */
  UIPanGestureRecognizer *twoFingerPan =
    [[UIPanGestureRecognizer alloc]
      initWithTarget:self action:@selector(handleTwoFingerPan:)];
  twoFingerPan.minimumNumberOfTouches = 2;
  twoFingerPan.maximumNumberOfTouches = 2;
  [self addGestureRecognizer:twoFingerPan];
  [twoFingerPan release];
  
  /* Single tap for click-to-position cursor.  */
  UITapGestureRecognizer *singleTap =
    [[UITapGestureRecognizer alloc]
      initWithTarget:self action:@selector(handleSingleTap:)];
  singleTap.numberOfTapsRequired = 1;
  /* Require double-tap to fail before recognizing single tap.  */
  [singleTap requireGestureRecognizerToFail:doubleTap];
  [self addGestureRecognizer:singleTap];
  [singleTap release];
  
  /* Now safe to release doubleTap.  */
  [doubleTap release];
  
  NSLog(@"setupGestureRecognizers: added %lu recognizers", (unsigned long)[self.gestureRecognizers count]);
}

/* Check if a point is within the Emacs content area.
   Since EmacsView is now constrained to the safe area by Auto Layout,
   coordinates from locationInView:self are already in Emacs coordinate space.
   No offset adjustment is needed - UIKit handles safe areas automatically.
   Returns YES if the point is within bounds, NO otherwise.  */
- (BOOL)isPointInBounds:(CGPoint)point
{
  struct frame *f = emacsframe;
  if (!f || !FRAME_LIVE_P (f))
    return NO;
    
  return (point.x >= 0 && point.y >= 0 &&
          point.x < FRAME_PIXEL_WIDTH (f) &&
          point.y < FRAME_PIXEL_HEIGHT (f));
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer
{
  if (recognizer.state == UIGestureRecognizerStateBegan)
    {
      IOSTRACE ("handleLongPress - generating right-click");

      CGPoint loc = [recognizer locationInView:self];
      if (![self isPointInBounds:loc])
        return;  /* Touch in safe area, ignore.  */
      
      struct frame *f = emacsframe;
      if (f == NULL || !FRAME_LIVE_P (f))
        return;

      /* Generate mouse-3 (right-click) event.  */
      struct input_event ie;
      EVENT_INIT (ie);
      ie.kind = MOUSE_CLICK_EVENT;
      ie.code = 2;  /* Button 3 (right-click).  */
      ie.modifiers = down_modifier;
      XSETFRAME (ie.frame_or_window, f);
      XSETINT (ie.x, (int) loc.x);
      XSETINT (ie.y, (int) loc.y);
      ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

      kbd_buffer_store_event (&ie);

      /* Immediately follow with up event.  */
      ie.modifiers = up_modifier;
      kbd_buffer_store_event (&ie);
      
      /* Signal that events are available.  */
      ios_signal_event_available ();
    }
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer
{
  CGPoint loc = [recognizer locationInView:self];
  
  /* EmacsView is constrained to safe area - coordinates are already in Emacs space.  */
  if (![self isPointInBounds:loc])
    return;
  
  NSLog(@"handleSingleTap - click at (%g, %g)", loc.x, loc.y);

  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Become first responder if not already.
     Don't toggle - that causes multiple focus events and cursor jumps.  */
  if (![self isFirstResponder])
    {
      [self becomeFirstResponder];
    }

  /* Generate mouse-1 click for positioning cursor.  */
  struct input_event ie;
  EVENT_INIT (ie);
  ie.kind = MOUSE_CLICK_EVENT;
  ie.code = 0;  /* Button 1.  */
  ie.modifiers = down_modifier;
  XSETFRAME (ie.frame_or_window, f);
  XSETINT (ie.x, (int) loc.x);
  XSETINT (ie.y, (int) loc.y);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  kbd_buffer_store_event (&ie);

  ie.modifiers = up_modifier;
  kbd_buffer_store_event (&ie);
  
  /* Signal that events are available.  */
  ios_signal_event_available ();
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer
{
  IOSTRACE ("handleDoubleTap - word selection");

  CGPoint loc = [recognizer locationInView:self];
  if (![self isPointInBounds:loc])
    return;
  
  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Generate double-click for word selection.  */
  struct input_event ie;
  EVENT_INIT (ie);
  ie.kind = MOUSE_CLICK_EVENT;
  ie.code = 0;  /* Button 1.  */
  ie.modifiers = down_modifier | click_modifier | double_modifier;
  XSETFRAME (ie.frame_or_window, f);
  XSETINT (ie.x, (int) loc.x);
  XSETINT (ie.y, (int) loc.y);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  kbd_buffer_store_event (&ie);

  ie.modifiers = up_modifier | click_modifier | double_modifier;
  kbd_buffer_store_event (&ie);
  
  /* Signal that events are available.  */
  ios_signal_event_available ();
}

- (void)handleTripleTap:(UITapGestureRecognizer *)recognizer
{
  IOSTRACE ("handleTripleTap - line selection");

  CGPoint loc = [recognizer locationInView:self];
  if (![self isPointInBounds:loc])
    return;
  
  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Generate triple-click for line selection.  */
  struct input_event ie;
  EVENT_INIT (ie);
  ie.kind = MOUSE_CLICK_EVENT;
  ie.code = 0;  /* Button 1.  */
  ie.modifiers = down_modifier | click_modifier | triple_modifier;
  XSETFRAME (ie.frame_or_window, f);
  XSETINT (ie.x, (int) loc.x);
  XSETINT (ie.y, (int) loc.y);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  kbd_buffer_store_event (&ie);

  ie.modifiers = up_modifier | click_modifier | triple_modifier;
  kbd_buffer_store_event (&ie);
  
  /* Signal that events are available.  */
  ios_signal_event_available ();
}

- (void)handleTwoFingerPan:(UIPanGestureRecognizer *)recognizer
{
  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  CGPoint translation = [recognizer translationInView:self];
  CGPoint loc = [recognizer locationInView:self];
  
  /* Clamp to frame bounds.  */
  if (loc.x < 0) loc.x = 0;
  if (loc.y < 0) loc.y = 0;
  if (loc.x >= FRAME_PIXEL_WIDTH (f)) loc.x = FRAME_PIXEL_WIDTH (f) - 1;
  if (loc.y >= FRAME_PIXEL_HEIGHT (f)) loc.y = FRAME_PIXEL_HEIGHT (f) - 1;

  if (recognizer.state == UIGestureRecognizerStateChanged)
    {
      IOSTRACE ("handleTwoFingerPan: dx=%g dy=%g", translation.x, translation.y);

      /* Convert pan to scroll events.  */
      struct input_event ie;
      EVENT_INIT (ie);
      ie.kind = WHEEL_EVENT;
      XSETFRAME (ie.frame_or_window, f);
      XSETINT (ie.x, (int) loc.x);
      XSETINT (ie.y, (int) loc.y);
      ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

      /* Determine scroll direction.  */
      if (fabs (translation.y) > fabs (translation.x))
        {
          /* Vertical scroll.  */
          ie.modifiers = 0;
          ie.arg = list3 (make_fixnum ((int) -translation.y),
                          make_fixnum (0),
                          make_fixnum (0));
        }
      else
        {
          /* Horizontal scroll.  */
          ie.modifiers = shift_modifier;
          ie.arg = list3 (make_fixnum (0),
                          make_fixnum ((int) -translation.x),
                          make_fixnum (0));
        }

      kbd_buffer_store_event (&ie);

      /* Reset translation so we get incremental values.  */
      [recognizer setTranslation:CGPointZero inView:self];
      
      /* Signal that events are available.  */
      ios_signal_event_available ();
    }
}

- (void)dealloc
{
  IOSTRACE ("EmacsView dealloc");
  
  /* Remove keyboard notification observers.  */
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  /* Stop any running key repeat timer.  */
  [keyRepeatTimer invalidate];
  keyRepeatTimer = nil;
  
  if (offscreenContext)
    CGContextRelease (offscreenContext);
  if (offscreenData)
    free (offscreenData);
  if (workingText != nil)
    [workingText release];
  [super dealloc];
}


/* ==========================================================================

   Drawing

   ========================================================================== */

- (void)drawRect:(CGRect)rect
{
  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f) || !f->output_data.ios)
    return;

  if (!f->glyphs_initialized_p)
    {
      /* Glyphs not initialized yet, schedule a redraw for later.  */
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                       [self setNeedsDisplay];
                     });
      return;
    }

  CGContextRef screenContext = UIGraphicsGetCurrentContext ();
  if (!screenContext)
    return;

  /* Ensure offscreen buffer exists and is the right size.  */
  [self ensureOffscreenContext];

  /* Blit the offscreen buffer to screen if it has content.
     If no content yet, the Emacs thread will draw during its event loop
     and call setNeedsDisplay when done.  Just show white for now.  */
  if (!offscreenHasContent)
    {
      /* Fill with background color while waiting for Emacs thread to draw.  */
      CGContextSetRGBFillColor (screenContext, 1.0, 1.0, 1.0, 1.0);
      CGContextFillRect (screenContext, rect);
      return;
    }

  NSLog(@"drawRect: offscreenContext=%p offscreenData=%p size=%zux%zu hasContent=%d",
        offscreenContext, offscreenData, offscreenWidth, offscreenHeight, offscreenHasContent);
  if (offscreenContext && offscreenData && offscreenWidth > 0 && offscreenHeight > 0)
    {
      /* Create an image from the offscreen bitmap data.
         Use @synchronized to prevent reading while Emacs thread is writing.  */
      @synchronized (self)
        {
          CGDataProviderRef provider = CGDataProviderCreateWithData (
            NULL, offscreenData, offscreenHeight * offscreenWidth * 4, NULL);
          CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB ();
          CGImageRef image = CGImageCreate (
            offscreenWidth, offscreenHeight,
            8, 32, offscreenWidth * 4,
            colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
            provider,
            NULL, false, kCGRenderingIntentDefault);
          CGColorSpaceRelease (colorSpace);
          CGDataProviderRelease (provider);
      
          if (image)
            {
              /* EmacsView is now constrained to safe area by Auto Layout.
                 No need to manually offset for safe areas - coordinates (0,0) 
                 is already at the top-left of the usable content area.
                 
                 The offscreen buffer was drawn with CoreGraphics coordinates (Y=0 at bottom).
                 UIKit screen context has Y=0 at top.
                 We need to flip Y axis to correct the image orientation.
                 
                 The offscreen buffer is at backing resolution (e.g., 2048×1536 for 2x scale).
                 Draw to the view's bounds (logical pixels) and let Core Graphics scale.  */
          
              CGFloat scale = backingScaleFactor > 0 ? backingScaleFactor : 1.0;
              CGFloat logicalWidth = offscreenWidth / scale;
              CGFloat logicalHeight = offscreenHeight / scale;
              
              CGContextSaveGState (screenContext);
          
              /* Flip Y axis for CoreGraphics image.
                 Translate by logical height, not backing height.  */
              CGContextTranslateCTM (screenContext, 0, logicalHeight);
              CGContextScaleCTM (screenContext, 1.0, -1.0);
          
              /* Draw the backing-resolution image into logical bounds.
                 Core Graphics will automatically use the full resolution.  */
              CGContextDrawImage (screenContext,
                                  CGRectMake (0, 0, logicalWidth, logicalHeight),
                                  image);
              CGContextRestoreGState (screenContext);
              CGImageRelease (image);
            }
        }
    }
  else
    {
      /* No offscreen buffer - just fill with background color.  */
      struct frame *f = emacsframe;
      struct face *face = f ? FRAME_DEFAULT_FACE (f) : NULL;
      unsigned long bgPixel = face ? face->background : 0;
      UIColor *bgColor = [UIColor colorWithUnsignedLong:bgPixel];
      CGContextSetFillColorWithColor (screenContext, bgColor.CGColor);
      CGContextFillRect (screenContext, rect);
    }
}

- (void)layoutSubviews
{
  [super layoutSubviews];

  /* Layout is now handled by EmacsViewController.
     Just ensure the display is refreshed.  */
  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;
    
  /* Only log if the size actually changes meaningfully.  */
  CGRect bounds = self.bounds;
  if (bounds.size.width > 0 && bounds.size.height > 0)
    {
      NSLog(@"EmacsView layoutSubviews: bounds=%@", NSStringFromCGRect(bounds));
    }
}

/* hitTest override for debugging (disabled) */


/* ==========================================================================

   Touch handling - convert to mouse events

   ========================================================================== */

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  UITouch *touch = [touches anyObject];
  CGPoint loc = [touch locationInView:self];
  
  /* EmacsView is constrained to safe area - no coordinate conversion needed.  */
  if (![self isPointInBounds:loc])
    return;

  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Convert touch to mouse down event.  */
  struct input_event ie;
  EVENT_INIT (ie);
  ie.kind = MOUSE_CLICK_EVENT;
  ie.code = 0;  /* Button 1.  */
  ie.modifiers = down_modifier;
  XSETFRAME (ie.frame_or_window, f);
  XSETINT (ie.x, (int) loc.x);
  XSETINT (ie.y, (int) loc.y);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  kbd_buffer_store_event (&ie);
  ios_signal_event_available ();
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  IOSTRACE ("touchesMoved");

  UITouch *touch = [touches anyObject];
  CGPoint loc = [touch locationInView:self];

  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Convert to touchscreen update event.  */
  struct input_event ie;
  EVENT_INIT (ie);
  ie.kind = TOUCHSCREEN_UPDATE_EVENT;
  XSETFRAME (ie.frame_or_window, f);
  XSETINT (ie.x, (int) loc.x);
  XSETINT (ie.y, (int) loc.y);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  kbd_buffer_store_event (&ie);
  ios_signal_event_available ();
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  IOSTRACE ("touchesEnded");

  UITouch *touch = [touches anyObject];
  CGPoint loc = [touch locationInView:self];

  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Convert touch to mouse up event.  */
  struct input_event ie;
  EVENT_INIT (ie);
  ie.kind = MOUSE_CLICK_EVENT;
  ie.code = 0;  /* Button 1.  */
  ie.modifiers = up_modifier;
  XSETFRAME (ie.frame_or_window, f);
  XSETINT (ie.x, (int) loc.x);
  XSETINT (ie.y, (int) loc.y);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  kbd_buffer_store_event (&ie);
  ios_signal_event_available ();
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  IOSTRACE ("touchesCancelled");
  /* Treat as touch ended.  */
  [self touchesEnded:touches withEvent:event];
}


/* ==========================================================================

   Keyboard input - UIKeyInput protocol

   ========================================================================== */

- (BOOL)canBecomeFirstResponder
{
  NSLog(@"EmacsView canBecomeFirstResponder: returning YES");
  return YES;
}

- (BOOL)canResignFirstResponder
{
  return YES;
}

- (BOOL)becomeFirstResponder
{
  /* Ensure accessory view exists before becoming first responder.  */
  (void)[self inputAccessoryView];
  
  BOOL result = [super becomeFirstResponder];
  NSLog(@"EmacsView becomeFirstResponder: result=%s accessoryView=%p", 
        result ? "YES" : "NO", sharedAccessoryView);
  
  if (result && emacsframe)
    {
      struct ios_display_info *dpyinfo = FRAME_DISPLAY_INFO (emacsframe);
      struct frame *old_focus = dpyinfo->ios_focus_frame;
      
      if (old_focus != emacsframe)
        {
          dpyinfo->ios_focus_frame = emacsframe;
          dpyinfo->highlight_frame = emacsframe;
          
          /* Generate FOCUS_IN_EVENT so Emacs knows this frame has focus.  */
          struct input_event ie;
          EVENT_INIT (ie);
          ie.kind = FOCUS_IN_EVENT;
          XSETFRAME (ie.frame_or_window, emacsframe);
          kbd_buffer_store_event (&ie);
          ios_signal_event_available ();
          
          NSLog(@"EmacsView: set focus to frame %p", emacsframe);
        }
    }
  
  return result;
}

- (BOOL)resignFirstResponder
{
  BOOL result = [super resignFirstResponder];
  NSLog(@"EmacsView resignFirstResponder: result=%s", result ? "YES" : "NO");
  
  if (result && emacsframe)
    {
      struct ios_display_info *dpyinfo = FRAME_DISPLAY_INFO (emacsframe);
      
      if (dpyinfo->ios_focus_frame == emacsframe)
        {
          /* Generate FOCUS_OUT_EVENT.  */
          struct input_event ie;
          EVENT_INIT (ie);
          ie.kind = FOCUS_OUT_EVENT;
          XSETFRAME (ie.frame_or_window, emacsframe);
          kbd_buffer_store_event (&ie);
          ios_signal_event_available ();
          
          dpyinfo->ios_focus_frame = NULL;
          NSLog(@"EmacsView: cleared focus from frame %p", emacsframe);
        }
    }
  
  return result;
}

/* UITextInputTraits properties - required for software keyboard.  */
- (UIKeyboardType)keyboardType
{
  return UIKeyboardTypeASCIICapable;
}

- (UITextAutocapitalizationType)autocapitalizationType
{
  return UITextAutocapitalizationTypeNone;
}

- (UITextAutocorrectionType)autocorrectionType
{
  return UITextAutocorrectionTypeNo;
}

- (UITextSpellCheckingType)spellCheckingType
{
  return UITextSpellCheckingTypeNo;
}

- (UITextSmartQuotesType)smartQuotesType API_AVAILABLE(ios(11.0))
{
  return UITextSmartQuotesTypeNo;
}

- (UITextSmartDashesType)smartDashesType API_AVAILABLE(ios(11.0))
{
  return UITextSmartDashesTypeNo;
}

- (UITextSmartInsertDeleteType)smartInsertDeleteType API_AVAILABLE(ios(11.0))
{
  return UITextSmartInsertDeleteTypeNo;
}

- (BOOL)hasText
{
  return workingText != nil && [workingText length] > 0;
}

- (void)insertText:(NSString *)text
{
  NSLog(@"insertText: '%@' (len=%lu) ctrl=%d meta=%d", 
        text, (unsigned long)[text length], modCtrl, modMeta);

  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Convert string input to key events.  */
  const char *utf8 = [text UTF8String];
  if (utf8 == NULL || *utf8 == '\0')
    return;

  NSUInteger len = [text length];
  for (NSUInteger i = 0; i < len; i++)
    {
      unichar c = [text characterAtIndex:i];

      struct input_event ie;
      EVENT_INIT (ie);
      ie.kind = ASCII_KEYSTROKE_EVENT;
      ie.code = c;
      ie.modifiers = 0;
      
      /* iOS sends '\n' (LF, code 10) for Enter key, but Emacs expects
         '\r' (CR, code 13) for RET. LF is C-j which evaluates in scratch.  */
      if (c == '\n')
        c = '\r';
      
      ie.code = c;
      
      /* Apply sticky modifiers from accessory bar.  */
      if (modCtrl)
        {
          /* Convert to control character for letters.  */
          if (c >= 'a' && c <= 'z')
            ie.code = c - 'a' + 1;
          else if (c >= 'A' && c <= 'Z')
            ie.code = c - 'A' + 1;
          else
            ie.modifiers |= ctrl_modifier;
        }
      if (modMeta)
        ie.modifiers |= meta_modifier;
      
      XSETFRAME (ie.frame_or_window, f);
      ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

      /* Handle non-ASCII characters.  */
      if (c > 127)
        ie.kind = MULTIBYTE_CHAR_KEYSTROKE_EVENT;

      kbd_buffer_store_event (&ie);
    }
  
  /* Signal that events are available to wake up the Emacs thread.  */
  ios_signal_event_available ();
  
  /* Clear sticky modifiers after use.  */
  [self clearModifiers];
}

- (void)deleteBackward
{
  NSLog(@"deleteBackward called");

  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  /* Send backspace key.  */
  struct input_event ie;
  EVENT_INIT (ie);
  ie.kind = ASCII_KEYSTROKE_EVENT;
  ie.code = 0x7f;  /* DEL.  */
  ie.modifiers = 0;
  XSETFRAME (ie.frame_or_window, f);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  kbd_buffer_store_event (&ie);
  
  /* Signal that events are available to wake up the Emacs thread.  */
  ios_signal_event_available ();
}


/* ==========================================================================

   Keyboard Accessory View - Emacs modifier keys

   This provides Esc, Ctrl, Alt/Meta, Tab and arrow keys above the virtual keyboard.
   Ctrl and Alt are sticky modifiers that apply to the next key pressed.

   ========================================================================== */

static UIView *sharedAccessoryView = nil;

- (UIView *)inputAccessoryView
{
  NSLog(@"inputAccessoryView called");
  if (sharedAccessoryView == nil)
    {
      NSLog(@"Creating sharedAccessoryView...");
      /* Create accessory view lazily to avoid init-time issues.  */
      CGFloat height = 44.0;
      
      UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, height)];
      bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
      bar.backgroundColor = [UIColor secondarySystemBackgroundColor];
      
      /* Create buttons.  */
      NSArray *titles = @[@"Esc", @"Ctrl", @"Alt", @"Tab", @"↵", @"↑", @"↓", @"←", @"→"];
      NSArray *actions = @[
        NSStringFromSelector(@selector(accessoryEsc:)),
        NSStringFromSelector(@selector(accessoryCtrl:)),
        NSStringFromSelector(@selector(accessoryAlt:)),
        NSStringFromSelector(@selector(accessoryTab:)),
        NSStringFromSelector(@selector(accessoryEnter:)),
        NSStringFromSelector(@selector(accessoryUp:)),
        NSStringFromSelector(@selector(accessoryDown:)),
        NSStringFromSelector(@selector(accessoryLeft:)),
        NSStringFromSelector(@selector(accessoryRight:))
      ];
      
      UIStackView *stack = [[UIStackView alloc] init];
      stack.axis = UILayoutConstraintAxisHorizontal;
      stack.distribution = UIStackViewDistributionFillEqually;
      stack.spacing = 4;
      stack.translatesAutoresizingMaskIntoConstraints = NO;
      [bar addSubview:stack];
      
      [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:4],
        [stack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-4],
        [stack.topAnchor constraintEqualToAnchor:bar.topAnchor constant:4],
        [stack.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-4]
      ]];
      
      for (NSUInteger i = 0; i < titles.count; i++)
        {
          UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
          [btn setTitle:titles[i] forState:UIControlStateNormal];
          btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
          btn.backgroundColor = [UIColor systemBackgroundColor];
          btn.layer.cornerRadius = 5;
          btn.tag = i;
          
          /* For repeatable keys (Enter, arrows), use touch-down with repeat timer.  */
          if (i >= 4)  /* Enter and arrows (indices 4-8) */
            {
              [btn addTarget:self 
                      action:@selector(accessoryKeyDown:) 
            forControlEvents:UIControlEventTouchDown];
              [btn addTarget:self 
                      action:@selector(accessoryKeyUp:) 
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            }
          else
            {
              /* Non-repeating keys (Esc, Ctrl, Alt, Tab).  */
              [btn addTarget:self 
                      action:NSSelectorFromString(actions[i]) 
            forControlEvents:UIControlEventTouchUpInside];
            }
          [stack addArrangedSubview:btn];
        }
      
      sharedAccessoryView = bar;
      NSLog(@"Created sharedAccessoryView: %p", sharedAccessoryView);
    }
  NSLog(@"Returning sharedAccessoryView: %p", sharedAccessoryView);
  return sharedAccessoryView;
}

- (void)updateAccessoryModifierButtons
{
  /* Update Ctrl and Alt button appearance based on state.  */
  if (sharedAccessoryView == nil) return;
  
  for (UIView *v in sharedAccessoryView.subviews)
    {
      if ([v isKindOfClass:[UIStackView class]])
        {
          UIStackView *stack = (UIStackView *)v;
          for (UIView *btn in stack.arrangedSubviews)
            {
              if ([btn isKindOfClass:[UIButton class]])
                {
                  UIButton *button = (UIButton *)btn;
                  if (button.tag == 1)  /* Ctrl */
                    {
                      button.backgroundColor = modCtrl ? 
                        [UIColor systemBlueColor] : [UIColor systemBackgroundColor];
                      [button setTitleColor:modCtrl ? 
                        [UIColor whiteColor] : [UIColor systemBlueColor]
                        forState:UIControlStateNormal];
                    }
                  else if (button.tag == 2)  /* Alt */
                    {
                      button.backgroundColor = modMeta ?
                        [UIColor systemOrangeColor] : [UIColor systemBackgroundColor];
                      [button setTitleColor:modMeta ?
                        [UIColor whiteColor] : [UIColor systemOrangeColor]
                        forState:UIControlStateNormal];
                    }
                }
            }
        }
    }
}

- (void)clearModifiers
{
  if (modCtrl || modMeta)
    {
      modCtrl = NO;
      modMeta = NO;
      [self updateAccessoryModifierButtons];
    }
}

- (void)accessoryEsc:(UIButton *)sender
{
  NSLog(@"accessoryEsc");
  struct frame *f = emacsframe;
  if (!f || !FRAME_LIVE_P(f)) return;
  
  struct input_event ie;
  EVENT_INIT(ie);
  ie.kind = NON_ASCII_KEYSTROKE_EVENT;
  ie.code = 0xFF1B;  /* XK_Escape */
  ie.modifiers = 0;
  XSETFRAME(ie.frame_or_window, f);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
  kbd_buffer_store_event(&ie);
  ios_signal_event_available();
}

- (void)accessoryCtrl:(UIButton *)sender
{
  modCtrl = !modCtrl;
  NSLog(@"accessoryCtrl: %s", modCtrl ? "ON" : "OFF");
  [self updateAccessoryModifierButtons];
}

- (void)accessoryAlt:(UIButton *)sender
{
  modMeta = !modMeta;
  NSLog(@"accessoryAlt: %s", modMeta ? "ON" : "OFF");
  [self updateAccessoryModifierButtons];
}

- (void)accessoryTab:(UIButton *)sender
{
  NSLog(@"accessoryTab");
  struct frame *f = emacsframe;
  if (!f || !FRAME_LIVE_P(f)) return;
  
  struct input_event ie;
  EVENT_INIT(ie);
  ie.kind = ASCII_KEYSTROKE_EVENT;
  ie.code = '\t';
  ie.modifiers = 0;
  if (modCtrl) ie.modifiers |= ctrl_modifier;
  if (modMeta) ie.modifiers |= meta_modifier;
  XSETFRAME(ie.frame_or_window, f);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
  kbd_buffer_store_event(&ie);
  ios_signal_event_available();
  [self clearModifiers];
}

- (void)accessoryEnter:(UIButton *)sender
{
  NSLog(@"accessoryEnter");
  struct frame *f = emacsframe;
  if (!f || !FRAME_LIVE_P(f)) return;
  
  struct input_event ie;
  EVENT_INIT(ie);
  ie.kind = ASCII_KEYSTROKE_EVENT;
  ie.code = '\r';  /* Return/Enter */
  ie.modifiers = 0;
  if (modCtrl) ie.modifiers |= ctrl_modifier;
  if (modMeta) ie.modifiers |= meta_modifier;
  XSETFRAME(ie.frame_or_window, f);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
  kbd_buffer_store_event(&ie);
  ios_signal_event_available();
  [self clearModifiers];
}

- (void)sendAccessoryArrow:(unsigned int)keysym
{
  struct frame *f = emacsframe;
  if (!f || !FRAME_LIVE_P(f)) return;
  
  struct input_event ie;
  EVENT_INIT(ie);
  ie.kind = NON_ASCII_KEYSTROKE_EVENT;
  ie.code = keysym;
  ie.modifiers = 0;
  if (modCtrl) ie.modifiers |= ctrl_modifier;
  if (modMeta) ie.modifiers |= meta_modifier;
  XSETFRAME(ie.frame_or_window, f);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
  kbd_buffer_store_event(&ie);
  ios_signal_event_available();
  [self clearModifiers];
}

- (void)accessoryUp:(UIButton *)sender { [self sendAccessoryArrow:0xFF52]; }
- (void)accessoryDown:(UIButton *)sender { [self sendAccessoryArrow:0xFF54]; }
- (void)accessoryLeft:(UIButton *)sender { [self sendAccessoryArrow:0xFF51]; }
- (void)accessoryRight:(UIButton *)sender { [self sendAccessoryArrow:0xFF53]; }

/* Key repeat support for Enter and arrow keys.  */

- (void)accessoryKeyDown:(UIButton *)sender
{
  /* Determine which action to perform based on button tag.  */
  SEL action = nil;
  switch (sender.tag)
    {
    case 4: action = @selector(accessoryEnter:); break;  /* Enter */
    case 5: action = @selector(accessoryUp:); break;     /* ↑ */
    case 6: action = @selector(accessoryDown:); break;   /* ↓ */
    case 7: action = @selector(accessoryLeft:); break;   /* ← */
    case 8: action = @selector(accessoryRight:); break;  /* → */
    default: return;
    }
  
  /* Perform the action immediately.  */
  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [self performSelector:action withObject:sender];
  #pragma clang diagnostic pop
  
  /* Start repeat timer after initial delay.  */
  keyRepeatAction = action;
  [keyRepeatTimer invalidate];
  keyRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.4  /* Initial delay */
                                                    target:self
                                                  selector:@selector(keyRepeatFired:)
                                                  userInfo:sender
                                                   repeats:NO];
}

- (void)keyRepeatFired:(NSTimer *)timer
{
  UIButton *sender = timer.userInfo;
  
  /* Perform the action.  */
  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [self performSelector:keyRepeatAction withObject:sender];
  #pragma clang diagnostic pop
  
  /* Continue repeating at faster rate.  */
  keyRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.05  /* Repeat rate */
                                                    target:self
                                                  selector:@selector(keyRepeatFired:)
                                                  userInfo:sender
                                                   repeats:NO];
}

- (void)accessoryKeyUp:(UIButton *)sender
{
  /* Stop key repeat.  */
  [keyRepeatTimer invalidate];
  keyRepeatTimer = nil;
  keyRepeatAction = nil;
}


/* ==========================================================================

   Keyboard notifications - handle show/hide for view relayout

   ========================================================================== */

- (void)keyboardWillHide:(NSNotification *)notification
{
  NSLog(@"keyboardWillHide: requesting full redisplay");
  
  /* When keyboard hides, request a full frame redisplay.
     The view size may have changed, and we need to clear any artifacts.
     
     NOTE: Don't call clearOffscreenWithBackgroundColor here - it can
     interfere with ongoing CA transactions and cause crashes.  */
  struct frame *f = emacsframe;
  if (f && FRAME_LIVE_P(f))
    {
      /* Mark frame as garbaged to force full redisplay.  */
      SET_FRAME_GARBAGED(f);
      
      /* Request expose to ensure redraw happens.  */
      extern void ios_request_expose(struct frame *f);
      ios_request_expose(f);
    }
  
  /* Force the view to relayout and redraw.  */
  [self setNeedsLayout];
  [self setNeedsDisplay];
}

- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
  NSLog(@"keyboardDidChangeFrame");
  
  /* Request redisplay when keyboard frame changes (e.g., undocking, resizing).  */
  struct frame *f = emacsframe;
  if (f && FRAME_LIVE_P(f))
    {
      SET_FRAME_GARBAGED(f);
      extern void ios_request_expose(struct frame *f);
      ios_request_expose(f);
    }
  
  [self setNeedsDisplay];
}


/* ==========================================================================

   Hardware keyboard handling (iOS 9+)

   ========================================================================== */

/* Map iOS HID key codes to X11 keysym codes (ORed with 0xFF00).
   These values match what keyboard.c expects for lispy_function_keys.  */
static unsigned int
ios_keycode_to_xkeysym (UIKeyboardHIDUsage keyCode)
{
  switch (keyCode)
    {
    /* Arrow keys.  */
    case UIKeyboardHIDUsageKeyboardUpArrow:
      return 0xFF52;  /* XK_Up.  */
    case UIKeyboardHIDUsageKeyboardDownArrow:
      return 0xFF54;  /* XK_Down.  */
    case UIKeyboardHIDUsageKeyboardLeftArrow:
      return 0xFF51;  /* XK_Left.  */
    case UIKeyboardHIDUsageKeyboardRightArrow:
      return 0xFF53;  /* XK_Right.  */

    /* Navigation keys.  */
    case UIKeyboardHIDUsageKeyboardHome:
      return 0xFF50;  /* XK_Home.  */
    case UIKeyboardHIDUsageKeyboardEnd:
      return 0xFF57;  /* XK_End.  */
    case UIKeyboardHIDUsageKeyboardPageUp:
      return 0xFF55;  /* XK_Page_Up (Prior).  */
    case UIKeyboardHIDUsageKeyboardPageDown:
      return 0xFF56;  /* XK_Page_Down (Next).  */
    case UIKeyboardHIDUsageKeyboardInsert:
      return 0xFF63;  /* XK_Insert.  */
    case UIKeyboardHIDUsageKeyboardDeleteForward:
      return 0xFF9F;  /* XK_KP_Delete / Delete.  */

    /* Function keys.  */
    case UIKeyboardHIDUsageKeyboardF1:
      return 0xFFBE;  /* XK_F1.  */
    case UIKeyboardHIDUsageKeyboardF2:
      return 0xFFBF;  /* XK_F2.  */
    case UIKeyboardHIDUsageKeyboardF3:
      return 0xFFC0;  /* XK_F3.  */
    case UIKeyboardHIDUsageKeyboardF4:
      return 0xFFC1;  /* XK_F4.  */
    case UIKeyboardHIDUsageKeyboardF5:
      return 0xFFC2;  /* XK_F5.  */
    case UIKeyboardHIDUsageKeyboardF6:
      return 0xFFC3;  /* XK_F6.  */
    case UIKeyboardHIDUsageKeyboardF7:
      return 0xFFC4;  /* XK_F7.  */
    case UIKeyboardHIDUsageKeyboardF8:
      return 0xFFC5;  /* XK_F8.  */
    case UIKeyboardHIDUsageKeyboardF9:
      return 0xFFC6;  /* XK_F9.  */
    case UIKeyboardHIDUsageKeyboardF10:
      return 0xFFC7;  /* XK_F10.  */
    case UIKeyboardHIDUsageKeyboardF11:
      return 0xFFC8;  /* XK_F11.  */
    case UIKeyboardHIDUsageKeyboardF12:
      return 0xFFC9;  /* XK_F12.  */

    /* Special keys.  */
    case UIKeyboardHIDUsageKeyboardEscape:
      return 0xFF1B;  /* XK_Escape.  */
    case UIKeyboardHIDUsageKeyboardDeleteOrBackspace:
      return 0xFF08;  /* XK_BackSpace.  */
    case UIKeyboardHIDUsageKeyboardTab:
      return 0xFF09;  /* XK_Tab.  */
    case UIKeyboardHIDUsageKeyboardReturnOrEnter:
      return 0xFF0D;  /* XK_Return.  */

    default:
      return 0;  /* Not a function key.  */
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses
           withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0))
{
  NSLog(@"pressesBegan: %lu presses", (unsigned long)[presses count]);

  BOOL handled = NO;

  for (UIPress *press in presses)
    {
      if (@available(iOS 13.4, *))
        {
          UIKey *key = press.key;
          if (key == nil)
            {
              NSLog(@"pressesBegan: key is nil");
              continue;
            }

          struct frame *f = emacsframe;
          if (f == NULL || !FRAME_LIVE_P (f))
            continue;

          /* Use characters (not charactersIgnoringModifiers) to get shifted chars.  */
          NSString *chars = key.characters;
          NSString *charsUnmod = key.charactersIgnoringModifiers;
          UIKeyModifierFlags mods = key.modifierFlags;
          UIKeyboardHIDUsage keyCode = key.keyCode;

          struct input_event ie;
          EVENT_INIT (ie);
          XSETFRAME (ie.frame_or_window, f);
          ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

          /* Build modifier mask.  */
          int emacs_modifiers = 0;
          if (mods & UIKeyModifierShift)
            emacs_modifiers |= shift_modifier;
          if (mods & UIKeyModifierControl)
            emacs_modifiers |= ctrl_modifier;
          if (mods & UIKeyModifierAlternate)
            emacs_modifiers |= meta_modifier;
          if (mods & UIKeyModifierCommand)
            emacs_modifiers |= super_modifier;

          ie.modifiers = emacs_modifiers;

          /* Check for function/special keys first.  */
          unsigned int xkeysym = ios_keycode_to_xkeysym (keyCode);
          if (xkeysym != 0)
            {
              ie.kind = NON_ASCII_KEYSTROKE_EVENT;
              ie.code = xkeysym;
              handled = YES;
              NSLog(@"pressesBegan: storing function key xkeysym=0x%x", xkeysym);
              kbd_buffer_store_event (&ie);
              
              /* Start key repeat timer for this key.  */
              [self startHWKeyRepeatWithEvent:ie];
            }
          else if ([chars length] == 1)
            {
              unichar c = [chars characterAtIndex:0];

              /* Handle control characters.  */
              if ((emacs_modifiers & ctrl_modifier) && c >= 'a' && c <= 'z')
                {
                  ie.code = c - 'a' + 1;  /* Convert to control char.  */
                  ie.modifiers &= ~ctrl_modifier;  /* Remove ctrl since it's encoded in char.  */
                  ie.kind = ASCII_KEYSTROKE_EVENT;
                }
              else if ((emacs_modifiers & ctrl_modifier) && c >= 'A' && c <= 'Z')
                {
                  ie.code = c - 'A' + 1;  /* Convert to control char.  */
                  ie.modifiers &= ~ctrl_modifier;
                  ie.kind = ASCII_KEYSTROKE_EVENT;
                }
              else
                {
                  ie.code = c;
                  ie.kind = (c > 127) ? MULTIBYTE_CHAR_KEYSTROKE_EVENT
                                      : ASCII_KEYSTROKE_EVENT;
                }

              handled = YES;
              NSLog(@"pressesBegan: storing char '%c' (0x%x) mods=0x%x", (char)ie.code, (unsigned)ie.code, ie.modifiers);
              kbd_buffer_store_event (&ie);
              
              /* Start key repeat timer for this key.  */
              [self startHWKeyRepeatWithEvent:ie];
            }
          else
            {
              NSLog(@"pressesBegan: chars='%@' length=%lu keyCode=0x%lx, not handled",
                    chars, (unsigned long)[chars length], (unsigned long)keyCode);
            }
        }
    }

  /* Signal that events are available to wake up the Emacs thread.  */
  if (handled)
    {
      NSLog(@"pressesBegan: signaling %d events available", (int)[presses count]);
      ios_signal_event_available ();
    }
    
  /* Only pass to super if we didn't handle it.  */
  if (!handled)
    [super pressesBegan:presses withEvent:event];
}

- (void)startHWKeyRepeatWithEvent:(struct input_event)ie
{
  /* Cancel any existing repeat timer.  */
  [self stopHWKeyRepeat];
  
  /* Store the event to repeat.  */
  hwKeyRepeatEvent = ie;
  hwKeyRepeatActive = YES;
  
  /* Start timer with initial delay of 400ms.  */
  hwKeyRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                      target:self
                                                    selector:@selector(hwKeyRepeatFired:)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)hwKeyRepeatFired:(NSTimer *)timer
{
  if (!hwKeyRepeatActive)
    return;
    
  /* Send the repeated key event.  */
  hwKeyRepeatEvent.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
  kbd_buffer_store_event (&hwKeyRepeatEvent);
  ios_signal_event_available ();
  
  /* Schedule next repeat with faster interval (50ms = 20 repeats/sec).  */
  hwKeyRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                      target:self
                                                    selector:@selector(hwKeyRepeatFired:)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)stopHWKeyRepeat
{
  hwKeyRepeatActive = NO;
  if (hwKeyRepeatTimer)
    {
      [hwKeyRepeatTimer invalidate];
      hwKeyRepeatTimer = nil;
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses
           withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0))
{
  IOSTRACE ("pressesEnded");
  
  /* Stop hardware key repeat when any key is released.  */
  [self stopHWKeyRepeat];
  
  [super pressesEnded:presses withEvent:event];
}

- (void)pressesChanged:(NSSet<UIPress *> *)presses
             withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0))
{
  [super pressesChanged:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses
               withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0))
{
  /* Stop hardware key repeat when key press is cancelled.  */
  [self stopHWKeyRepeat];
  [super pressesCancelled:presses withEvent:event];
}

/* UIKeyCommand support for intercepted keys (C-c, C-x, etc.)  */
- (NSArray<UIKeyCommand *> *)keyCommands
{
  static NSMutableArray<UIKeyCommand *> *commands = nil;

  if (commands == nil)
    {
      commands = [[NSMutableArray alloc] init];

      /* Add commands for Control+letter combinations that iOS might intercept.  */
      NSString *letters = @"abcdefghijklmnopqrstuvwxyz";
      for (NSUInteger i = 0; i < [letters length]; i++)
        {
          NSString *letter = [letters substringWithRange:NSMakeRange(i, 1)];
          UIKeyCommand *cmd = [UIKeyCommand keyCommandWithInput:letter
                                                  modifierFlags:UIKeyModifierControl
                                                         action:@selector(handleKeyCommand:)];
          cmd.wantsPriorityOverSystemBehavior = YES;
          [commands addObject:cmd];
        }

      /* Add Meta+letter combinations.  */
      for (NSUInteger i = 0; i < [letters length]; i++)
        {
          NSString *letter = [letters substringWithRange:NSMakeRange(i, 1)];
          UIKeyCommand *cmd = [UIKeyCommand keyCommandWithInput:letter
                                                  modifierFlags:UIKeyModifierAlternate
                                                         action:@selector(handleKeyCommand:)];
          [commands addObject:cmd];
        }
        
      /* Add Command+letter combinations (Super modifier in Emacs).  */
      for (NSUInteger i = 0; i < [letters length]; i++)
        {
          NSString *letter = [letters substringWithRange:NSMakeRange(i, 1)];
          UIKeyCommand *cmd = [UIKeyCommand keyCommandWithInput:letter
                                                  modifierFlags:UIKeyModifierCommand
                                                         action:@selector(handleKeyCommand:)];
          cmd.wantsPriorityOverSystemBehavior = YES;
          [commands addObject:cmd];
        }

      /* Add Escape.  */
      UIKeyCommand *escCmd = [UIKeyCommand keyCommandWithInput:UIKeyInputEscape
                                                 modifierFlags:0
                                                        action:@selector(handleKeyCommand:)];
      [commands addObject:escCmd];

      /* Add Tab with modifiers.  */
      UIKeyCommand *tabCmd = [UIKeyCommand keyCommandWithInput:@"\t"
                                                 modifierFlags:UIKeyModifierControl
                                                        action:@selector(handleKeyCommand:)];
      [commands addObject:tabCmd];
      
      /* C-Space (set-mark-command).  */
      UIKeyCommand *cSpaceCmd = [UIKeyCommand keyCommandWithInput:@" "
                                                    modifierFlags:UIKeyModifierControl
                                                           action:@selector(handleKeyCommand:)];
      cSpaceCmd.wantsPriorityOverSystemBehavior = YES;
      [commands addObject:cSpaceCmd];
      
      /* C-@ (set-mark-command, same as C-Space).  */
      UIKeyCommand *cAtCmd = [UIKeyCommand keyCommandWithInput:@"@"
                                                 modifierFlags:UIKeyModifierControl
                                                        action:@selector(handleKeyCommand:)];
      cAtCmd.wantsPriorityOverSystemBehavior = YES;
      [commands addObject:cAtCmd];
      
      /* Return/Enter key.  */
      UIKeyCommand *returnCmd = [UIKeyCommand keyCommandWithInput:@"\r"
                                                    modifierFlags:0
                                                           action:@selector(handleKeyCommand:)];
      [commands addObject:returnCmd];
      
      /* C-Return (sometimes used in Emacs).  */
      UIKeyCommand *cReturnCmd = [UIKeyCommand keyCommandWithInput:@"\r"
                                                     modifierFlags:UIKeyModifierControl
                                                            action:@selector(handleKeyCommand:)];
      [commands addObject:cReturnCmd];
      
      /* Arrow keys - add these so key repeat works.  */
      UIKeyCommand *upCmd = [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow
                                                modifierFlags:0
                                                       action:@selector(handleKeyCommand:)];
      [commands addObject:upCmd];
      
      UIKeyCommand *downCmd = [UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow
                                                  modifierFlags:0
                                                         action:@selector(handleKeyCommand:)];
      [commands addObject:downCmd];
      
      UIKeyCommand *leftCmd = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow
                                                  modifierFlags:0
                                                         action:@selector(handleKeyCommand:)];
      [commands addObject:leftCmd];
      
      UIKeyCommand *rightCmd = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow
                                                   modifierFlags:0
                                                          action:@selector(handleKeyCommand:)];
      [commands addObject:rightCmd];
      
      /* Arrow keys with modifiers.  */
      NSArray *arrowInputs = @[UIKeyInputUpArrow, UIKeyInputDownArrow, 
                               UIKeyInputLeftArrow, UIKeyInputRightArrow];
      NSArray *modifierSets = @[@(UIKeyModifierControl), @(UIKeyModifierAlternate),
                                @(UIKeyModifierShift), @(UIKeyModifierCommand)];
      for (NSString *arrow in arrowInputs)
        {
          for (NSNumber *modNum in modifierSets)
            {
              UIKeyCommand *cmd = [UIKeyCommand keyCommandWithInput:arrow
                                                      modifierFlags:[modNum unsignedIntegerValue]
                                                             action:@selector(handleKeyCommand:)];
              [commands addObject:cmd];
            }
        }
    }

  return commands;
}

- (void)handleKeyCommand:(UIKeyCommand *)command
{
  NSLog(@"handleKeyCommand: input='%@' mods=0x%lx", command.input, (unsigned long)command.modifierFlags);
  
  struct frame *f = emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;

  NSString *input = command.input;
  UIKeyModifierFlags mods = command.modifierFlags;

  struct input_event ie;
  EVENT_INIT (ie);
  XSETFRAME (ie.frame_or_window, f);
  ie.timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  /* Build modifier mask.  */
  int emacs_modifiers = 0;
  if (mods & UIKeyModifierShift)
    emacs_modifiers |= shift_modifier;
  if (mods & UIKeyModifierControl)
    emacs_modifiers |= ctrl_modifier;
  if (mods & UIKeyModifierAlternate)
    emacs_modifiers |= meta_modifier;
  if (mods & UIKeyModifierCommand)
    emacs_modifiers |= super_modifier;

  /* Handle special inputs.  */
  if ([input isEqualToString:UIKeyInputEscape])
    {
      ie.kind = ASCII_KEYSTROKE_EVENT;
      ie.code = 27;  /* ESC.  */
      ie.modifiers = emacs_modifiers;
    }
  /* Handle arrow keys.  */
  else if ([input isEqualToString:UIKeyInputUpArrow])
    {
      ie.kind = NON_ASCII_KEYSTROKE_EVENT;
      ie.code = 0xFF52;  /* XK_Up */
      ie.modifiers = emacs_modifiers;
    }
  else if ([input isEqualToString:UIKeyInputDownArrow])
    {
      ie.kind = NON_ASCII_KEYSTROKE_EVENT;
      ie.code = 0xFF54;  /* XK_Down */
      ie.modifiers = emacs_modifiers;
    }
  else if ([input isEqualToString:UIKeyInputLeftArrow])
    {
      ie.kind = NON_ASCII_KEYSTROKE_EVENT;
      ie.code = 0xFF51;  /* XK_Left */
      ie.modifiers = emacs_modifiers;
    }
  else if ([input isEqualToString:UIKeyInputRightArrow])
    {
      ie.kind = NON_ASCII_KEYSTROKE_EVENT;
      ie.code = 0xFF53;  /* XK_Right */
      ie.modifiers = emacs_modifiers;
    }
  else if ([input length] == 1)
    {
      unichar c = [input characterAtIndex:0];

      /* Handle Control+Space (set-mark-command).  */
      if ((emacs_modifiers & ctrl_modifier) && c == ' ')
        {
          ie.code = 0;  /* C-@ / C-Space = NUL character.  */
          ie.modifiers = emacs_modifiers & ~ctrl_modifier;
          ie.kind = ASCII_KEYSTROKE_EVENT;
        }
      /* Handle Control+@ (set-mark-command).  */
      else if ((emacs_modifiers & ctrl_modifier) && c == '@')
        {
          ie.code = 0;  /* C-@ = NUL character.  */
          ie.modifiers = emacs_modifiers & ~ctrl_modifier;
          ie.kind = ASCII_KEYSTROKE_EVENT;
        }
      /* Handle Return/Enter key.  */
      else if (c == '\r')
        {
          ie.code = 13;  /* CR / Return.  */
          ie.modifiers = emacs_modifiers;
          ie.kind = ASCII_KEYSTROKE_EVENT;
        }
      /* For Control+letter, generate the control character.  */
      else if ((emacs_modifiers & ctrl_modifier) && c >= 'a' && c <= 'z')
        {
          ie.code = c - 'a' + 1;
          ie.modifiers = emacs_modifiers & ~ctrl_modifier;
          ie.kind = ASCII_KEYSTROKE_EVENT;
        }
      else
        {
          ie.code = c;
          ie.modifiers = emacs_modifiers;
          ie.kind = (c > 127) ? MULTIBYTE_CHAR_KEYSTROKE_EVENT
                              : ASCII_KEYSTROKE_EVENT;
        }
    }
  else
    {
      return;  /* Unknown input.  */
    }

  kbd_buffer_store_event (&ie);
  ios_signal_event_available ();
}


/* ==========================================================================

   Frame management

   ========================================================================== */

- (void)setWindowClosing:(BOOL)closing
{
  windowClosing = closing;
}

- (void)deleteWorkingText
{
  if (workingText != nil)
    {
      [workingText release];
      workingText = nil;
    }
  processingCompose = NO;
}

- (void)handleFS
{
  /* TODO: Handle fullscreen toggle.  */
}

- (void)setFSValue:(int)value
{
  fs_state = value;
}

- (int)fullscreenState
{
  return fs_state;
}

- (void)toggleFullScreen:(id)sender
{
  /* On iOS, apps are typically always fullscreen.  */
  IOSTRACE ("toggleFullScreen - no-op on iOS");
}

- (BOOL)isFullscreen
{
  /* iOS apps are typically always fullscreen.  */
  return YES;
}

- (void)windowDidBecomeKey
{
  IOSTRACE ("windowDidBecomeKey");
  struct frame *f = emacsframe;
  if (f && FRAME_LIVE_P (f))
    {
      /* Post focus in event.  */
      struct input_event ie;
      EVENT_INIT (ie);
      ie.kind = FOCUS_IN_EVENT;
      XSETFRAME (ie.frame_or_window, f);

      kbd_buffer_store_event (&ie);
      ios_signal_event_available ();
    }
}

- (void)windowDidResignKey
{
  IOSTRACE ("windowDidResignKey");
  struct frame *f = emacsframe;
  if (f && FRAME_LIVE_P (f))
    {
      /* Post focus out event.  */
      struct input_event ie;
      EVENT_INIT (ie);
      ie.kind = FOCUS_OUT_EVENT;
      XSETFRAME (ie.frame_or_window, f);

      kbd_buffer_store_event (&ie);
      ios_signal_event_available ();
    }
}

- (void)setFrame:(CGRect)frame
{
  [super setFrame:frame];
  IOSTRACE ("setFrame: %g x %g", frame.size.width, frame.size.height);
}

- (UIEdgeInsets)safeAreaInsets
{
  return [super safeAreaInsets];
}

- (void)safeAreaInsetsDidChange
{
  [super safeAreaInsetsDidChange];
  IOSTRACE ("safeAreaInsetsDidChange");
  [self setNeedsLayout];
}

- (void)copyRect:(CGRect)srcRect to:(CGPoint)dest
{
  @synchronized (self)
    {
      if (!offscreenContext || !offscreenData)
        return;

      /* Input coordinates are in logical (Emacs) pixels.
         Convert to backing pixels for bitmap manipulation.  */
      CGFloat scale = backingScaleFactor > 0 ? backingScaleFactor : 1.0;
      
      int src_x = (int)(srcRect.origin.x * scale);
      int src_y = (int)(srcRect.origin.y * scale);
      int dst_x = (int)(dest.x * scale);
      int dst_y = (int)(dest.y * scale);
      int width = (int)(srcRect.size.width * scale);
      int height = (int)(srcRect.size.height * scale);

      NSLog(@"copyRect: logical src=(%d,%d) dst=(%d,%d) size=%dx%d -> backing scale=%.1f offscreen=%zux%zu",
            (int)srcRect.origin.x, (int)srcRect.origin.y, (int)dest.x, (int)dest.y, 
            (int)srcRect.size.width, (int)srcRect.size.height, scale, offscreenWidth, offscreenHeight);

      /* Clamp to buffer bounds.  */
      if (src_x < 0) { width += src_x; dst_x -= src_x; src_x = 0; }
      if (src_y < 0) { height += src_y; dst_y -= src_y; src_y = 0; }
      if (dst_x < 0) { width += dst_x; src_x -= dst_x; dst_x = 0; }
      if (dst_y < 0) { height += dst_y; src_y -= dst_y; dst_y = 0; }
      if (src_x + width > (int)offscreenWidth) width = (int)offscreenWidth - src_x;
      if (src_y + height > (int)offscreenHeight) height = (int)offscreenHeight - src_y;
      if (dst_x + width > (int)offscreenWidth) width = (int)offscreenWidth - dst_x;
      if (dst_y + height > (int)offscreenHeight) height = (int)offscreenHeight - dst_y;

      if (width <= 0 || height <= 0)
        {
          NSLog(@"  copyRect: clamped to zero, returning");
          return;
        }

      /* Copy row by row, handling overlap correctly.  */
      size_t bytesPerRow = offscreenWidth * 4;
      size_t copyBytes = width * 4;

      /* Convert Emacs Y to memory row.
         In CGBitmapContext: row 0 in memory = CG Y=0 = bottom of screen.
         We draw with Y-flip, so Emacs Y=0 -> CG Y=(height-1) -> memory row (height-1).
         For a block: memory_row_start = offscreenHeight - emacs_y - block_height.  */
      int mem_src_y = (int)offscreenHeight - src_y - height;
      int mem_dst_y = (int)offscreenHeight - dst_y - height;

      NSLog(@"  copyRect: mem_src_y=%d mem_dst_y=%d (copying %d rows)", 
            mem_src_y, mem_dst_y, height);

      if (mem_dst_y < mem_src_y)
        {
          /* Copying upward in memory - start from top (low addresses).  */
          NSLog(@"  copyRect: copying UP in memory (top to bottom)");
          for (int row = 0; row < height; row++)
            {
              uint8_t *srcRow = offscreenData + (mem_src_y + row) * bytesPerRow + src_x * 4;
              uint8_t *dstRow = offscreenData + (mem_dst_y + row) * bytesPerRow + dst_x * 4;
              memmove (dstRow, srcRow, copyBytes);
            }
        }
      else
        {
          /* Copying downward in memory - start from bottom (high addresses).  */
          NSLog(@"  copyRect: copying DOWN in memory (bottom to top)");
          for (int row = height - 1; row >= 0; row--)
            {
              uint8_t *srcRow = offscreenData + (mem_src_y + row) * bytesPerRow + src_x * 4;
              uint8_t *dstRow = offscreenData + (mem_dst_y + row) * bytesPerRow + dst_x * 4;
              memmove (dstRow, srcRow, copyBytes);
            }
        }
    }
}
- (void)ensureOffscreenContext
{
  /* Use frame pixel dimensions instead of self.bounds to match Emacs coordinate space.  */
  struct frame *f = emacsframe;
  if (f && FRAME_LIVE_P (f))
    {
      size_t w = (size_t) FRAME_PIXEL_WIDTH (f);
      size_t h = (size_t) FRAME_PIXEL_HEIGHT (f);
      if (w > 0 && h > 0)
        {
          [self ensureOffscreenContextForWidth:w height:h];
        }
    }
}

- (void)ensureOffscreenContextForWidth:(size_t)width height:(size_t)height
{
  @synchronized (self)
    {
      /* For Retina displays, create buffer at backing pixel dimensions.
         Store logical dimensions for comparison, but allocate at scale.  */
      CGFloat scale = backingScaleFactor > 0 ? backingScaleFactor : 1.0;
      size_t backingWidth = (size_t)(width * scale);
      size_t backingHeight = (size_t)(height * scale);
      
      /* Check if we need to recreate the offscreen context.
         Compare against logical dimensions since that's what Emacs uses.  */
      if (offscreenContext && offscreenWidth == backingWidth && offscreenHeight == backingHeight)
        return;
    
      /* Free old context and data.  */
      if (offscreenContext)
        {
          CGContextRelease (offscreenContext);
          offscreenContext = NULL;
        }
      if (offscreenData)
        {
          free (offscreenData);
          offscreenData = NULL;
        }
  
      /* Mark that we have no valid content after resize.  */
      offscreenHasContent = false;
    
      if (width == 0 || height == 0)
        {
          offscreenWidth = 0;
          offscreenHeight = 0;
          return;
        }
    
      /* Allocate the bitmap data at backing pixel dimensions.  */
      size_t bytesPerRow = backingWidth * 4;  /* RGBA */
      offscreenData = calloc (backingHeight, bytesPerRow);
      if (!offscreenData)
        {
          NSLog(@"ensureOffscreenContext: failed to allocate %zu bytes", backingHeight * bytesPerRow);
          return;
        }
    
      /* Create the bitmap context at backing pixel dimensions.  */
      CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB ();
      offscreenContext = CGBitmapContextCreate (offscreenData,
                                                backingWidth, backingHeight,
                                                8,  /* bits per component */
                                                bytesPerRow,
                                                colorSpace,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
      CGColorSpaceRelease (colorSpace);
  
      if (!offscreenContext)
        {
          NSLog(@"ensureOffscreenContext: failed to create context");
          free (offscreenData);
          offscreenData = NULL;
          return;
        }
    
      offscreenWidth = backingWidth;
      offscreenHeight = backingHeight;
  
      /* Apply scale transform so all drawing uses logical coordinates.
         CoreGraphics Y=0 is at bottom, and we draw with transformed Y coords.
         After this, drawing at (x, y) in logical coords goes to (x*scale, y*scale) backing.  */
      CGContextScaleCTM (offscreenContext, scale, scale);

      /* Fill with the frame's background color (default to white if not set).  */
      CGFloat r = 1, g = 1, b = 1, a = 1;
      if (emacsframe)
        {
          struct ios_output *output = emacsframe->output_data.ios;
          UIColor *bgColor = output ? output->background_color : nil;
          if (bgColor)
            [bgColor getRed:&r green:&g blue:&b alpha:&a];
        }
      CGContextSetRGBFillColor (offscreenContext, r, g, b, a);
      /* Fill in logical coordinates (scale transform applied).  */
      CGContextFillRect (offscreenContext, CGRectMake (0, 0, width, height));

      NSLog(@"ensureOffscreenContext: created %zu x %zu backing (%zux%zu logical) scale=%.1f bg=(%f,%f,%f)", 
            backingWidth, backingHeight, width, height, scale, r, g, b);
    }
}

- (CGContextRef)getOffscreenContext
{
  @synchronized (self)
    {
      /* Check for pending resize from main thread.
         Processing it here (on Emacs thread) avoids race conditions.  */
      if (pendingResizeWidth > 0 && pendingResizeHeight > 0)
        {
          size_t newW = pendingResizeWidth;
          size_t newH = pendingResizeHeight;
          pendingResizeWidth = 0;
          pendingResizeHeight = 0;
          [self ensureOffscreenContextForWidth:newW height:newH];
        }
      
      if (!offscreenContext)
        {
          /* Use frame pixel dimensions instead of self.bounds to be thread-safe.
             self.bounds is a UIKit property that can only be accessed from main thread.  */
          struct frame *f = emacsframe;
          if (f && FRAME_LIVE_P (f))
            {
              size_t w = (size_t) FRAME_PIXEL_WIDTH (f);
              size_t h = (size_t) FRAME_PIXEL_HEIGHT (f);
              if (w > 0 && h > 0)
                [self ensureOffscreenContextForWidth:w height:h];
            }
        }
      return offscreenContext;
    }
}

- (void)markOffscreenHasContent
{
  @synchronized (self)
    {
      offscreenHasContent = YES;
    }
}

- (void)clearOffscreenWithBackgroundColor
{
  @synchronized (self)
    {
      needsBackgroundClear = YES;

      /* If we have an offscreen context, clear it now with the frame's background color.  */
      if (offscreenContext && emacsframe)
        {
          struct ios_output *output = emacsframe->output_data.ios;
          UIColor *bgColor = output ? output->background_color : nil;

          CGFloat r = 0, g = 0, b = 0, a = 1;
          if (bgColor)
            [bgColor getRed:&r green:&g blue:&b alpha:&a];

          CGContextSetRGBFillColor (offscreenContext, r, g, b, a);
          CGContextFillRect (offscreenContext, CGRectMake (0, 0, offscreenWidth, offscreenHeight));

          /* Mark that we need a full redraw.  */
          offscreenHasContent = NO;
          needsBackgroundClear = NO;
        }
    }
}

/* Handle CALayer layout - check for garbaged frames and trigger redisplay.
   This is critical for handling resize properly.  When a frame is resized,
   SET_FRAME_GARBAGED is called, and this method ensures redisplay happens
   at the right point in the run loop.  Copied from NS port.  */
- (void)layoutSublayersOfLayer:(CALayer *)layer
{
  struct frame *f = emacsframe;
  if (!f || !FRAME_LIVE_P (f))
    return;

  /* Check if frame dimensions match our offscreen buffer.  */
  int frame_width = FRAME_PIXEL_WIDTH (f);
  int frame_height = FRAME_PIXEL_HEIGHT (f);
  
  @synchronized (self)
    {
      /* offscreenWidth/Height are in backing pixels (logical × scale).
         FRAME_PIXEL_WIDTH/HEIGHT are in logical pixels.
         Compare in logical pixels for consistency.  */
      CGFloat scale = backingScaleFactor > 0 ? backingScaleFactor : 1.0;
      size_t logicalWidth = offscreenWidth / scale;
      size_t logicalHeight = offscreenHeight / scale;
      
      /* If frame size differs from offscreen buffer, set pending resize.
         Don't free the context here - let the Emacs thread do it safely
         in getOffscreenContext to avoid use-after-free during drawing.  */
      if (offscreenContext && 
          (logicalWidth != (size_t)frame_width || logicalHeight != (size_t)frame_height))
        {
          NSLog(@"layoutSublayersOfLayer: buffer size mismatch %zux%zu vs frame %dx%d, setting pending resize",
                logicalWidth, logicalHeight, frame_width, frame_height);
          pendingResizeWidth = frame_width;
          pendingResizeHeight = frame_height;
          /* Mark content as stale so next draw recreates.  */
          offscreenHasContent = NO;
        }
    }

  /* If frame is garbaged, signal the Emacs thread to redisplay.
     We cannot call redisplay() directly from the main thread because
     Emacs internals are not thread-safe. Instead, we set a flag and
     wake up the Emacs thread, which will handle it in ios_read_socket.  */
  if (FRAME_GARBAGED_P (f))
    {
      NSLog(@"layoutSublayersOfLayer: frame is garbaged, requesting expose on Emacs thread");
      extern void ios_request_expose (struct frame *f);
      ios_request_expose (f);
    }
}

@end


/* ==========================================================================

   EmacsViewController - View controller for Emacs frames

   ========================================================================== */

@implementation EmacsViewController
{
  CGFloat _keyboardHeight;
  BOOL _keyboardVisible;
  NSLayoutConstraint *_bottomConstraint;  /* For keyboard avoidance.  */
}

- (instancetype)initWithFrame:(struct frame *)f
{
  IOSTRACE ("EmacsViewController initWithFrame");
  self = [super init];
  if (self)
    {
      /* Use the existing EmacsView from the frame, don't create a new one.  */
      _emacsView = FRAME_IOS_VIEW (f);
      _keyboardHeight = 0;
      _keyboardVisible = NO;
    }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  /* Set a background color for the safe area regions (status bar, home indicator).  */
  self.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.12 alpha:1.0];
  
  /* Add EmacsView as a subview constrained to the safe area.
     This lets UIKit handle safe area insets automatically - no manual offsets needed.
     EmacsView coordinates (0,0) will be at the top-left of the SAFE AREA,
     not the top-left of the screen.  */
  _emacsView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:_emacsView];
  
  /* Constrain to safe area on all sides except bottom (for keyboard).  */
  UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
  _bottomConstraint = [_emacsView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor];
  
  [NSLayoutConstraint activateConstraints:@[
    [_emacsView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
    [_emacsView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
    [_emacsView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
    _bottomConstraint
  ]];
  
  /* Register for keyboard notifications.  */
  [[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(keyboardWillShow:)
           name:UIKeyboardWillShowNotification
         object:nil];
  [[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(keyboardWillHide:)
           name:UIKeyboardWillHideNotification
         object:nil];
  [[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(keyboardDidChangeFrame:)
           name:UIKeyboardDidChangeFrameNotification
         object:nil];
  
  NSLog(@"EmacsViewController viewDidLoad: emacsView=%p, constraints set to safe area", _emacsView);
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  NSLog(@"EmacsViewController viewWillAppear");
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  
  /* Force a redraw after the view has appeared.  */
  [_emacsView setNeedsDisplay];
  
  /* Make the view first responder for keyboard input.  */
  [_emacsView becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
  [super viewDidDisappear:animated];
  NSLog(@"EmacsViewController viewDidDisappear");
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  
  /* EmacsView is now constrained to safe area by Auto Layout.
     Its bounds represent the actual usable content area.  */
  struct frame *f = _emacsView->emacsframe;
  if (f == NULL || !FRAME_LIVE_P (f))
    return;
  
  CGRect emacsViewBounds = _emacsView.bounds;
  int newWidth = (int)emacsViewBounds.size.width;
  int newHeight = (int)emacsViewBounds.size.height;
  
  /* Clamp to positive values.  */
  if (newWidth < 1) newWidth = 1;
  if (newHeight < 1) newHeight = 1;
  
  NSLog(@"EmacsViewController viewDidLayoutSubviews: emacsView.bounds=%@ effectiveSize=%dx%d currentSize=%dx%d",
        NSStringFromCGRect(emacsViewBounds),
        newWidth, newHeight,
        FRAME_PIXEL_WIDTH(f), FRAME_PIXEL_HEIGHT(f));
  
  /* No need to store contentInsets anymore - UIKit handles safe areas.  */
  _emacsView->keyboardHeight = _keyboardHeight;
  
  /* Notify Emacs of size change if needed.  */
  if (newWidth != FRAME_PIXEL_WIDTH(f) || newHeight != FRAME_PIXEL_HEIGHT(f))
    {
      extern void ios_request_frame_resize (struct frame *f, int width, int height);
      ios_request_frame_resize (f, newWidth, newHeight);
    }
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  NSLog(@"EmacsViewController viewWillTransitionToSize: %g x %g", size.width, size.height);
  
  /* Schedule a layout pass after the transition completes.
     This ensures the frame resize happens at the right time for Stage Manager.  */
  [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
  }];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
  [super traitCollectionDidChange:previousTraitCollection];
  NSLog(@"EmacsViewController traitCollectionDidChange");

  /* Handle dark/light mode changes.  */
  if (@available(iOS 13.0, *))
    {
      if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection])
        {
          /* Notify Emacs of appearance change.  */
          UIUserInterfaceStyle style = self.traitCollection.userInterfaceStyle;
          Lisp_Object appearance = (style == UIUserInterfaceStyleDark)
            ? Qdark : Qlight;
          Vios_system_appearance = appearance;

          /* Run hook.  */
          if (!NILP (Vios_system_appearance_change_functions))
            safe_calln (Qrun_hook_with_args,
                        Qios_system_appearance_change_functions);
        }
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
  if (@available(iOS 13.0, *))
    return UIStatusBarStyleDefault;
  return UIStatusBarStyleDefault;
}

- (BOOL)prefersStatusBarHidden
{
  return NO;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
  /* Allow Emacs to handle edge gestures.  */
  return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
  return YES;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
  NSDictionary *info = [notification userInfo];
  CGRect keyboardFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGRect localFrame = [self.view convertRect:keyboardFrame fromView:nil];
  
  /* Calculate how much the keyboard overlaps our view.  */
  CGFloat overlap = CGRectGetMaxY(self.view.bounds) - localFrame.origin.y;
  if (overlap < 0) overlap = 0;
  
  /* Subtract safe area bottom since our constraint is relative to safe area.  */
  CGFloat safeAreaBottom = self.view.safeAreaInsets.bottom;
  _keyboardHeight = overlap > safeAreaBottom ? overlap - safeAreaBottom : 0;
  _keyboardVisible = YES;
  
  NSLog(@"keyboardWillShow: overlap=%g safeBottom=%g adjustedHeight=%g", 
        overlap, safeAreaBottom, _keyboardHeight);
  
  /* Animate the constraint change along with the keyboard.  */
  NSNumber *duration = [info objectForKey:UIKeyboardAnimationDurationUserInfoKey];
  NSNumber *curve = [info objectForKey:UIKeyboardAnimationCurveUserInfoKey];
  
  _bottomConstraint.constant = -_keyboardHeight;
  
  [UIView animateWithDuration:[duration doubleValue]
                        delay:0
                      options:[curve unsignedIntegerValue] << 16
                   animations:^{
    [self.view layoutIfNeeded];
  } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
  NSDictionary *info = [notification userInfo];
  NSNumber *duration = [info objectForKey:UIKeyboardAnimationDurationUserInfoKey];
  NSNumber *curve = [info objectForKey:UIKeyboardAnimationCurveUserInfoKey];
  
  _keyboardHeight = 0;
  _keyboardVisible = NO;
  _bottomConstraint.constant = 0;
  
  NSLog(@"keyboardWillHide");
  
  [UIView animateWithDuration:[duration doubleValue]
                        delay:0
                      options:[curve unsignedIntegerValue] << 16
                   animations:^{
    [self.view layoutIfNeeded];
  } completion:nil];
}

- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
  if (!_keyboardVisible)
    return;
  
  NSDictionary *info = [notification userInfo];
  CGRect keyboardFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGRect localFrame = [self.view convertRect:keyboardFrame fromView:nil];
  
  CGFloat overlap = CGRectGetMaxY(self.view.bounds) - localFrame.origin.y;
  if (overlap < 0) overlap = 0;
  CGFloat safeAreaBottom = self.view.safeAreaInsets.bottom;
  CGFloat newHeight = overlap > safeAreaBottom ? overlap - safeAreaBottom : 0;
  
  if (newHeight != _keyboardHeight)
    {
      _keyboardHeight = newHeight;
      _bottomConstraint.constant = -_keyboardHeight;
      NSLog(@"keyboardDidChangeFrame: height=%g", _keyboardHeight);
      [self.view layoutIfNeeded];
    }
}

@end


/* ==========================================================================

   Local declarations

   ========================================================================== */

/* Convert iOS key codes to X keysym-compatible values.  */
static unsigned convert_ios_to_X_keysym[] =
{
  /* Arrow keys.  */
  UIKeyboardHIDUsageKeyboardLeftArrow,   0x51,
  UIKeyboardHIDUsageKeyboardUpArrow,     0x52,
  UIKeyboardHIDUsageKeyboardRightArrow,  0x53,
  UIKeyboardHIDUsageKeyboardDownArrow,   0x54,
  UIKeyboardHIDUsageKeyboardPageUp,      0x55,
  UIKeyboardHIDUsageKeyboardPageDown,    0x56,
  UIKeyboardHIDUsageKeyboardHome,        0x50,
  UIKeyboardHIDUsageKeyboardEnd,         0x57,

  /* Function keys.  */
  UIKeyboardHIDUsageKeyboardF1,          0xBE,
  UIKeyboardHIDUsageKeyboardF2,          0xBF,
  UIKeyboardHIDUsageKeyboardF3,          0xC0,
  UIKeyboardHIDUsageKeyboardF4,          0xC1,
  UIKeyboardHIDUsageKeyboardF5,          0xC2,
  UIKeyboardHIDUsageKeyboardF6,          0xC3,
  UIKeyboardHIDUsageKeyboardF7,          0xC4,
  UIKeyboardHIDUsageKeyboardF8,          0xC5,
  UIKeyboardHIDUsageKeyboardF9,          0xC6,
  UIKeyboardHIDUsageKeyboardF10,         0xC7,
  UIKeyboardHIDUsageKeyboardF11,         0xC8,
  UIKeyboardHIDUsageKeyboardF12,         0xC9,

  /* Special keys.  */
  UIKeyboardHIDUsageKeyboardDeleteOrBackspace, 0x08,
  UIKeyboardHIDUsageKeyboardDeleteForward,     0xFF,
  UIKeyboardHIDUsageKeyboardTab,               0x09,
  UIKeyboardHIDUsageKeyboardReturnOrEnter,     0x0D,
  UIKeyboardHIDUsageKeyboardEscape,            0x1B,

  0, 0  /* Terminator.  */
};

/* On iOS, use system antialiasing.  */
float ios_antialias_threshold;

NSString *ios_app_name = @"Emacs";

/* Display variables.  */
struct ios_display_info *ios_display_list;
long context_menu_value = 0;

/* Display update.  */
static struct frame *ios_updating_frame;
static int ios_window_num = 0;
static BOOL gsaved = NO;

/* Event loop.  */
static BOOL send_appdefined = YES;
#define NO_APPDEFINED_DATA (-8)
static int last_appdefined_event_data = NO_APPDEFINED_DATA;
static NSTimer *timed_entry = nil;
static fd_set select_readfds, select_writefds;
enum { SELECT_HAVE_READ = 1, SELECT_HAVE_WRITE = 2, SELECT_HAVE_TMO = 4 };
static int select_nfds = 0, select_valid = 0;
static struct timespec select_timeout = { 0, 0 };
static int selfds[2] = { -1, -1 };
static pthread_mutex_t select_mutex;
static NSAutoreleasePool *outerpool;
static struct input_event *emacs_event = NULL;
static struct input_event *q_event_ptr = NULL;
static int n_emacs_events_pending = 0;
static NSMutableArray *ios_pending_files;
static BOOL ios_do_open_file = NO;

/* Non-zero means that a HELP_EVENT has been generated since Emacs start.  */
static BOOL any_help_event_p = NO;

/* ==========================================================================

   UIWindow/UIViewController Connection
   
   Emacs creates frames but the iOS app owns the UIWindow.
   This mechanism connects the two.

   ========================================================================== */

/* The main UIWindow, set by the app delegate/scene delegate.  */
static UIWindow *ios_main_window = nil;

/* The main EmacsViewController, set when first frame is created.  */
static EmacsViewController *ios_main_view_controller = nil;

/* Set the main window from the app.  Called from EmacsSceneDelegate.  */
void
ios_set_main_window (UIWindow *window)
{
  IOSTRACE ("ios_set_main_window: %p", window);
  ios_main_window = window;
}

/* Get the main window.  */
UIWindow *
ios_get_main_window (void)
{
  return ios_main_window;
}

/* Connect an Emacs frame to the UIWindow.
   Called from iosfns.m when creating the initial frame.  */
void
ios_connect_frame_to_window (struct frame *f)
{
  IOSTRACE ("ios_connect_frame_to_window");

  if (ios_main_window == nil)
    {
      IOSTRACE ("Error: ios_main_window is nil");
      return;
    }

  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view == nil)
    {
      IOSTRACE ("Error: frame has no EmacsView");
      return;
    }

  /* All UIKit operations MUST happen on the main thread.
     Use synchronous dispatch to ensure the view is connected before we return.  */
  dispatch_sync (dispatch_get_main_queue (), ^{
    /* Create the view controller for this frame.  */
    EmacsViewController *vc = [[EmacsViewController alloc] initWithFrame:f];
    
    /* If this is the first frame, set it as root view controller.  */
    if (ios_main_view_controller == nil)
      {
        ios_main_view_controller = vc;
        ios_main_window.rootViewController = vc;
        [ios_main_window makeKeyAndVisible];
        
        /* Trigger initial display of the EmacsView.  */
        [view setNeedsDisplay];
        
        IOSTRACE ("Set rootViewController, made window visible, triggered display");
        
        /* Make the view first responder after a short delay to allow
           the view controller transition to complete.  */
        dispatch_after (dispatch_time (DISPATCH_TIME_NOW, 
                                       (int64_t)(0.5 * NSEC_PER_SEC)),
                        dispatch_get_main_queue (), ^{
          BOOL result = [view becomeFirstResponder];
          NSLog (@"ios_connect_frame_to_window: delayed becomeFirstResponder=%s, isFirstResponder=%s",
                 result ? "YES" : "NO",
                 [view isFirstResponder] ? "YES" : "NO");
        });
      }
    else
      {
        /* For additional frames (child frames), add as a subview.  */
        [ios_main_view_controller.view addSubview:view];
      }
  });
}

static struct {
  struct input_event *q;
  int nr, cap;
} hold_event_q = {
  NULL, 0, 0
};


/* ==========================================================================

   Modifier key handling

   ========================================================================== */

/* Convert modifier flags from UIKeyModifierFlags to Emacs modifiers.  */
static unsigned int
ios_ev_modifiers (UIKeyModifierFlags flags)
{
  unsigned int modifiers = 0;

  if (flags & UIKeyModifierShift)
    modifiers |= shift_modifier;
  if (flags & UIKeyModifierControl)
    modifiers |= ctrl_modifier;
  if (flags & UIKeyModifierAlternate)  /* Option/Alt key -> Meta */
    modifiers |= meta_modifier;
  if (flags & UIKeyModifierCommand)    /* Command key -> Super */
    modifiers |= super_modifier;

  return modifiers;
}

/* Convert touch event to button/modifier info.  */
#define EV_TIMESTAMP(e) ([[e timestamp] timeIntervalSince1970] * 1000)


/* ==========================================================================

   Event handling utilities

   ========================================================================== */

void
ios_init_events (struct input_event *ev)
{
  EVENT_INIT (*ev);
  emacs_event = ev;
}

void
ios_finish_events (void)
{
  emacs_event = NULL;
}

static void
hold_event (struct input_event *event)
{
  if (hold_event_q.nr == hold_event_q.cap)
    {
      if (hold_event_q.cap == 0)
        hold_event_q.cap = 10;
      else
        hold_event_q.cap *= 2;
      hold_event_q.q = xrealloc (hold_event_q.q,
                                  hold_event_q.cap * sizeof *hold_event_q.q);
    }

  hold_event_q.q[hold_event_q.nr++] = *event;
}

static void
ios_send_appdefined (int data)
{
  /* On iOS, we use a different mechanism than NSEvent.
     For now, just set the flag.  */
  last_appdefined_event_data = data;
  send_appdefined = NO;
}


/* ==========================================================================

   Frame and display utilities

   ========================================================================== */

Lisp_Object
ios_get_focus_frame (struct frame *f)
{
  Lisp_Object lisp_focus;
  struct frame *focus = FRAME_DISPLAY_INFO (f)->ios_focus_frame;

  if (!focus)
    return Qnil;

  XSETFRAME (lisp_focus, focus);
  return lisp_focus;
}

static void
ios_focus_frame (struct frame *f, bool noactivate)
{
  struct ios_display_info *dpyinfo = FRAME_DISPLAY_INFO (f);
  dpyinfo->ios_focus_frame = f;
}

static void
ios_frame_rehighlight (struct frame *f)
{
  /* On iOS, we don't have the same focus model as desktop.
     The current frame is always highlighted.  */
  struct ios_display_info *dpyinfo = FRAME_DISPLAY_INFO (f);
  struct frame *old_highlight = dpyinfo->highlight_frame;

  if (old_highlight != f)
    {
      dpyinfo->highlight_frame = f;
      if (old_highlight)
        gui_update_cursor (old_highlight, true);
      if (f)
        gui_update_cursor (f, true);
    }
}


/* ==========================================================================

   Mouse/touch position

   ========================================================================== */

static void
ios_mouse_position (struct frame **fp, int insist, Lisp_Object *bar_window,
                    enum scroll_bar_part *part, Lisp_Object *x, Lisp_Object *y,
                    Time *timestamp)
{
  /* On iOS, we track touch position instead of mouse.  */
  struct ios_display_info *dpyinfo = FRAME_DISPLAY_INFO (*fp);

  if (dpyinfo->last_mouse_motion_frame)
    {
      *fp = dpyinfo->last_mouse_motion_frame;
      *x = make_fixnum (dpyinfo->last_mouse_motion_x);
      *y = make_fixnum (dpyinfo->last_mouse_motion_y);
      *timestamp = dpyinfo->last_mouse_movement_time;
    }

  *bar_window = Qnil;
  *part = scroll_bar_above_handle;
}


/* ==========================================================================

   System appearance (dark/light mode)

   ========================================================================== */

/* Run the system appearance change hook.  */
static void
run_system_appearance_change_hook (void)
{
  if (NILP (Vios_system_appearance_change_functions))
    return;

  block_input ();

  bool owfi = waiting_for_input;
  waiting_for_input = false;

  safe_calln (Qrun_hook_with_args,
              Qios_system_appearance_change_functions,
              Vios_system_appearance);
  Fredisplay (Qt);

  waiting_for_input = owfi;

  unblock_input ();
}

/* Called when the system appearance changes (light/dark mode).
   This is triggered from the EmacsViewController's traitCollectionDidChange.  */
void
ios_handle_appearance_change (bool is_dark)
{
  Lisp_Object new_appearance = is_dark ? Qdark : Qlight;

  if (!EQ (Vios_system_appearance, new_appearance))
    {
      Vios_system_appearance = new_appearance;
      run_system_appearance_change_hook ();
    }
}

/* Initialize system appearance at startup.  */
void
ios_init_system_appearance (void)
{
  @autoreleasepool {
    UITraitCollection *traits = [UITraitCollection currentTraitCollection];
    bool is_dark = (traits.userInterfaceStyle == UIUserInterfaceStyleDark);
    Vios_system_appearance = is_dark ? Qdark : Qlight;

    /* Run the hook at startup.  */
    pending_funcalls = Fcons (list3 (Qrun_hook_with_args,
                                     Qios_system_appearance_change_functions,
                                     Vios_system_appearance),
                              pending_funcalls);
  }
}


/* ==========================================================================

   Alpha elements (per-element transparency control)

   ========================================================================== */

/* Check if a specific element type should respect alpha-background.  */
bool
ios_alpha_element_enabled (struct frame *f, Lisp_Object element)
{
  Lisp_Object elements = FRAME_IOS_ALPHA_ELEMENTS (f);

  /* If nil or ios-alpha-all, all elements are transparent.  */
  if (NILP (elements) || EQ (elements, Qios_alpha_all))
    return true;

  /* If it's a list, check if element is a member.  */
  if (CONSP (elements))
    return !NILP (Fmemq (element, elements));

  return false;
}

/* Set the alpha-elements frame parameter.  */
void
ios_set_alpha_elements (struct frame *f, Lisp_Object new_value,
                        Lisp_Object old_value)
{
  IOSTRACE ("ios_set_alpha_elements");

  if (NILP (new_value) || EQ (new_value, Qios_alpha_all) || CONSP (new_value))
    {
      FRAME_IOS_ALPHA_ELEMENTS (f) = new_value;
      SET_FRAME_GARBAGED (f);
    }
  else
    error ("Invalid `ios-alpha-elements' value");
}


/* ==========================================================================

   Background blur

   ========================================================================== */

/* Tag for identifying our blur effect view.  */
#define IOS_BLUR_VIEW_TAG 0xB10E

/* Apply background blur effect to frame.  */
void
ios_update_background_blur (struct frame *f)
{
  IOSTRACE ("ios_update_background_blur");

  EmacsView *view = FRAME_IOS_VIEW (f);
  if (!view)
    return;

  int blur_radius = FRAME_IOS_BACKGROUND_BLUR (f);
  CGFloat alpha = f->alpha_background;

  /* Dispatch to main thread for UIKit operations.  */
  dispatch_async (dispatch_get_main_queue (), ^{
    /* Find existing blur view if any.  */
    UIVisualEffectView *existingBlurView = nil;
    for (UIView *subview in view.subviews)
      {
        if (subview.tag == IOS_BLUR_VIEW_TAG && [subview isKindOfClass:[UIVisualEffectView class]])
          {
            existingBlurView = (UIVisualEffectView *)subview;
            break;
          }
      }

    /* Only apply blur if we have transparency and blur radius.  */
    if (alpha >= 1.0 || blur_radius <= 0)
      {
        /* Remove existing blur view if present.  */
        if (existingBlurView)
          {
            [existingBlurView removeFromSuperview];
          }
        return;
      }

    /* Determine blur style based on appearance and intensity.  */
    UIBlurEffectStyle style;
    if (@available(iOS 13.0, *))
      {
        /* Use system material styles that adapt to light/dark mode.  */
        if (blur_radius > 20)
          style = UIBlurEffectStyleSystemThickMaterial;
        else if (blur_radius > 10)
          style = UIBlurEffectStyleSystemMaterial;
        else
          style = UIBlurEffectStyleSystemThinMaterial;
      }
    else
      {
        /* Fallback for older iOS.  */
        style = UIBlurEffectStyleDark;
      }

    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:style];

    if (existingBlurView)
      {
        /* Update existing blur view's effect.  */
        existingBlurView.effect = blurEffect;
        existingBlurView.alpha = MIN (1.0, (CGFloat)blur_radius / 30.0);
      }
    else
      {
        /* Create new blur view.  */
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurView.frame = view.bounds;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blurView.tag = IOS_BLUR_VIEW_TAG;
        blurView.alpha = MIN (1.0, (CGFloat)blur_radius / 30.0);
        blurView.userInteractionEnabled = NO;  /* Let touches pass through.  */

        /* Insert at the back, behind the Emacs content.  */
        [view insertSubview:blurView atIndex:0];
      }
  });
}

/* Set the background blur frame parameter.  */
void
ios_set_background_blur (struct frame *f, Lisp_Object new_value,
                         Lisp_Object old_value)
{
  IOSTRACE ("ios_set_background_blur");

  int blur = 0;

  if (NILP (new_value))
    blur = 0;
  else if (FIXNUMP (new_value))
    {
      EMACS_INT val = XFIXNUM (new_value);
      if (val < 0)
        error ("Invalid `ios-background-blur' value");
      blur = (val > INT_MAX) ? INT_MAX : (int) val;
    }
  else if (FLOATP (new_value))
    {
      double val = XFLOAT_DATA (new_value);
      if (val < 0)
        error ("Invalid `ios-background-blur' value");
      blur = (val > INT_MAX) ? INT_MAX : (int) val;
    }
  else
    error ("Invalid `ios-background-blur' value");

  FRAME_IOS_BACKGROUND_BLUR (f) = blur;
  ios_update_background_blur (f);
}


/* ==========================================================================

   Frame visibility

   ========================================================================== */

void
ios_make_frame_visible (struct frame *f)
{
  IOSTRACE ("ios_make_frame_visible");

  if (!FRAME_VISIBLE_P (f))
    {
      EmacsView *view = FRAME_IOS_VIEW (f);
      if (view)
        {
          [view setHidden:NO];
          SET_FRAME_VISIBLE (f, true);
          
          /* Mark the frame as needing a full redisplay.
             This ensures that redisplay_internal will redraw the frame
             when the command loop runs.  */
          SET_FRAME_GARBAGED (f);
          fset_redisplay (f);
          windows_or_buffers_changed = 1;
        }
    }
}

void
ios_make_frame_invisible (struct frame *f)
{
  IOSTRACE ("ios_make_frame_invisible");

  if (FRAME_VISIBLE_P (f))
    {
      EmacsView *view = FRAME_IOS_VIEW (f);
      if (view)
        {
          [view setHidden:YES];
          SET_FRAME_VISIBLE (f, false);
        }
    }
}

static void
ios_make_frame_visible_invisible (struct frame *f, bool visible)
{
  if (visible)
    ios_make_frame_visible (f);
  else
    ios_make_frame_invisible (f);
}

void
ios_iconify_frame (struct frame *f)
{
  /* On iOS, there's no concept of iconifying.
     The app is either active, background, or suspended.
     This is a no-op for compatibility.  */
  IOSTRACE ("ios_iconify_frame (no-op on iOS)");
}

static void
ios_fullscreen_hook (struct frame *f)
{
  /* On iOS, apps are always full screen or in split view.
     This is handled by the system.  */
  IOSTRACE ("ios_fullscreen_hook");
}


/* ==========================================================================

   Frame sizing

   ========================================================================== */

static void
ios_set_window_size (struct frame *f, bool change_gravity,
                     int width, int height)
{
  IOSTRACE ("ios_set_window_size: %dx%d", width, height);

  /* On iOS, window size is typically controlled by the system.
     We can request size changes for Split View scenarios.  */
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view)
    {
      /* Update internal frame size tracking.  */
      int old_width = FRAME_PIXEL_WIDTH (f);
      int old_height = FRAME_PIXEL_HEIGHT (f);

      if (width != old_width || height != old_height)
        {
          /* Notify Emacs of the size change.  */
          change_frame_size (f, width, height, false, true, false);
        }
    }
}

static void
ios_set_window_size_and_position (struct frame *f, int width, int height)
{
  IOSTRACE ("ios_set_window_size_and_position: %dx%d", width, height);

  /* On iOS, position is generally not user-controllable.  */
  ios_set_window_size (f, false, width, height);
}

void
ios_set_offset (struct frame *f, int xoff, int yoff, int change_gravity)
{
  /* On iOS, frame position is controlled by the system.  */
  IOSTRACE ("ios_set_offset (limited on iOS)");
}

static void
ios_set_frame_alpha (struct frame *f)
{
  struct ios_output *output = f->output_data.ios;
  EmacsView *view = output->view;
  CGFloat alpha = f->alpha[0];

  if (alpha < 0.0)
    alpha = 1.0;
  else if (alpha > 1.0)
    alpha = 1.0;

  if (view)
    [view setAlpha:alpha];
}


/* ==========================================================================

   Scroll bars

   ========================================================================== */

static void
ios_set_vertical_scroll_bar (struct window *w, int portion, int whole, int position)
{
  /* TODO: Implement scroll bar using UIScrollView or custom view.  */
  IOSTRACE ("ios_set_vertical_scroll_bar");
}

static void
ios_set_horizontal_scroll_bar (struct window *w, int portion, int whole, int position)
{
  IOSTRACE ("ios_set_horizontal_scroll_bar");
}

void
ios_set_scroll_bar_default_width (struct frame *f)
{
  /* On iOS, scroll bars are typically thin indicators.  */
  int width = 8;
  FRAME_CONFIG_SCROLL_BAR_WIDTH (f) = width;
  FRAME_CONFIG_SCROLL_BAR_COLS (f) = (width + FRAME_COLUMN_WIDTH (f) - 1)
    / FRAME_COLUMN_WIDTH (f);
}

void
ios_set_scroll_bar_default_height (struct frame *f)
{
  int height = 8;
  FRAME_CONFIG_SCROLL_BAR_HEIGHT (f) = height;
  FRAME_CONFIG_SCROLL_BAR_LINES (f) = (height + FRAME_LINE_HEIGHT (f) - 1)
    / FRAME_LINE_HEIGHT (f);
}

static void
ios_condemn_scroll_bars (struct frame *f)
{
  /* Mark all scroll bars for potential removal.  */
  IOSTRACE ("ios_condemn_scroll_bars");
}

static void
ios_redeem_scroll_bar (struct window *w)
{
  /* Unmark this window's scroll bar.  */
  IOSTRACE ("ios_redeem_scroll_bar");
}

static void
ios_judge_scroll_bars (struct frame *f)
{
  /* Remove scroll bars that are still condemned.  */
  IOSTRACE ("ios_judge_scroll_bars");
}


/* ==========================================================================

   Tab bar

   ========================================================================== */

void
ios_change_tab_bar_height (struct frame *f, int height)
{
  IOSTRACE ("ios_change_tab_bar_height: %d", height);

  int unit = FRAME_LINE_HEIGHT (f);
  int old_height = FRAME_TAB_BAR_HEIGHT (f);

  /* Ensure height is a multiple of the character height.  */
  height = (height + unit - 1) / unit * unit;

  if (height != old_height)
    {
      FRAME_TAB_BAR_HEIGHT (f) = height;
      FRAME_TAB_BAR_LINES (f) = height / unit;

      adjust_frame_size (f, -1, -1, 3, false, Qtab_bar_lines);
    }
}


/* ==========================================================================

   Drawing

   ========================================================================== */

/* Forward declarations.  */
static void ios_update_begin (struct frame *f);
static void ios_update_end (struct frame *f);
static CGContextRef ios_get_drawing_context (struct frame *f);

static void
ios_frame_up_to_date (struct frame *f)
{
  /* Called when frame is fully updated.
     Fix up mouse highlighting right after a full update.
     NOTE: Do NOT call setNeedsDisplay here - that would cause an infinite
     redisplay loop since drawRect calls expose_frame which triggers another
     frame_up_to_date call.  */
  IOSTRACE ("ios_frame_up_to_date");

  if (FRAME_IOS_P (f))
    {
      Mouse_HLInfo *hlinfo = MOUSE_HL_INFO (f);
      if (f == hlinfo->mouse_face_mouse_frame)
        {
          block_input ();
          ios_update_begin (f);
          note_mouse_highlight (hlinfo->mouse_face_mouse_frame,
                                hlinfo->mouse_face_mouse_x,
                                hlinfo->mouse_face_mouse_y);
          ios_update_end (f);
          unblock_input ();
        }
    }
}

void
ios_clear_frame (struct frame *f)
{
  IOSTRACE ("ios_clear_frame");
  NSLog(@"ios_clear_frame called");

  /* Clear the entire offscreen buffer with background color.  */
  CGContextRef context = ios_get_drawing_context (f);
  if (context)
    {
      struct face *face = FRAME_DEFAULT_FACE (f);
      unsigned long bg = face ? face->background : 0;
      CGFloat r = ((bg >> 16) & 0xFF) / 255.0;
      CGFloat g = ((bg >> 8) & 0xFF) / 255.0;
      CGFloat b = (bg & 0xFF) / 255.0;
      
      NSLog(@"ios_clear_frame: bg=0x%lx (r=%.2f g=%.2f b=%.2f) size=%dx%d", 
            bg, r, g, b, FRAME_PIXEL_WIDTH (f), FRAME_PIXEL_HEIGHT (f));
      
      CGContextSetRGBFillColor (context, r, g, b, 1.0);
      CGContextFillRect (context, CGRectMake (0, 0, 
                                              FRAME_PIXEL_WIDTH (f),
                                              FRAME_PIXEL_HEIGHT (f)));
    }
  else
    {
      NSLog(@"ios_clear_frame: no context!");
    }

  /* Mark that content has changed and request display.  */
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view)
    {
      [view markOffscreenHasContent];
      ios_request_display (view);
    }
}

/* Convert Emacs Y coordinate to CoreGraphics Y coordinate.
   Emacs: Y=0 at top, increases downward.
   CoreGraphics: Y=0 at bottom, increases upward.
   For a rect at Emacs (x, y) with height h, CG y = frame_height - y - h.
   For a point at Emacs (x, y), CG y = frame_height - y.  */
static inline CGFloat
ios_cg_y_for_emacs_y (struct frame *f, int emacs_y, int height)
{
  return FRAME_PIXEL_HEIGHT (f) - emacs_y - height;
}

static inline CGFloat
ios_cg_y_for_emacs_point (struct frame *f, int emacs_y)
{
  return FRAME_PIXEL_HEIGHT (f) - emacs_y;
}

static void
ios_clear_frame_area (struct frame *f, int x, int y, int width, int height)
{
  static int clear_count = 0;
  clear_count++;
  if (clear_count <= 5 || clear_count % 50 == 0)
    NSLog(@"ios_clear_frame_area: count=%d emacs=(%d,%d) %dx%d -> cg=(%d,%.0f) frame_h=%d", 
          clear_count, x, y, width, height, x, ios_cg_y_for_emacs_y(f, y, height), FRAME_PIXEL_HEIGHT(f));

  CGContextRef context = ios_get_drawing_context (f);
  if (!context)
    return;
    
  /* Get background color.  */
  struct face *face = FRAME_DEFAULT_FACE (f);
  unsigned long bg = face ? face->background : 0;
  
  CGFloat r = ((bg >> 16) & 0xFF) / 255.0;
  CGFloat g = ((bg >> 8) & 0xFF) / 255.0;
  CGFloat b = (bg & 0xFF) / 255.0;
  
  /* Convert Emacs Y to CoreGraphics Y (Y=0 at bottom).  */
  CGFloat cg_y = ios_cg_y_for_emacs_y (f, y, height);
  
  CGContextSetRGBFillColor (context, r, g, b, 1.0);
  CGContextFillRect (context, CGRectMake (x, cg_y, width, height));
  
  /* Mark offscreen buffer as having content.  */
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view)
    [view markOffscreenHasContent];
}

static void
ios_ring_bell (struct frame *f)
{
  IOSTRACE ("ios_ring_bell");

  /* On iOS, we can use haptic feedback or system sound.  */
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 100000
  UIImpactFeedbackGenerator *generator =
    [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
  [generator prepare];
  [generator impactOccurred];
  [generator release];
#endif
}

static void
ios_update_begin (struct frame *f)
{
  static int update_count = 0;
  update_count++;
  if (update_count <= 5 || update_count % 50 == 0)
    NSLog(@"ios_update_begin: count=%d frame=%p", update_count, f);
  IOSTRACE ("ios_update_begin");
  ios_updating_frame = f;
  
  /* Note: By the time we're called, face_change has already been cleared
     by init_iterator in xdisp.c.  We detect face changes in ios_update_end
     by comparing the realized default face background with what we last
     cleared the frame with.  */
}

static void
ios_update_end (struct frame *f)
{
  static int update_count = 0;
  update_count++;
  if (update_count <= 5 || update_count % 50 == 0)
    NSLog(@"ios_update_end: count=%d frame=%p", update_count, f);
  IOSTRACE ("ios_update_end");
  ios_updating_frame = NULL;
  
  /* After drawing, check if the default face background has changed from
     what we last cleared the frame with.  This catches theme changes that
     we missed in ios_update_begin because faces weren't yet re-realized.  */
  struct ios_output *output = f->output_data.ios;
  if (output && FRAME_FACE_CACHE (f))
    {
      struct face *face = FRAME_DEFAULT_FACE (f);
      if (face)
        {
          unsigned long current_bg = face->background;
          /* Debug: log every 20th call to see face background values */
          if (update_count <= 10 || update_count % 20 == 0)
            NSLog(@"ios_update_end[%d]: face bg=0x%lx last=0x%lx", 
                  update_count, current_bg, output->last_face_background);
          if (output->last_face_background != current_bg)
            {
              NSLog(@"ios_update_end: BACKGROUND CHANGED from 0x%lx to 0x%lx, triggering full redraw",
                    output->last_face_background, current_bg);
              output->last_face_background = current_bg;
              
              /* Convert the face background color to UIColor.  */
              CGFloat r = ((current_bg >> 16) & 0xFF) / 255.0;
              CGFloat g = ((current_bg >> 8) & 0xFF) / 255.0;
              CGFloat b = (current_bg & 0xFF) / 255.0;
              UIColor *bgColor = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
              
              /* Update output->background_color so clearOffscreenWithBackgroundColor uses it.  */
              if (output->background_color)
                [output->background_color release];
              output->background_color = [bgColor retain];
              
              /* Update EmacsView's backgroundColor and clear offscreen.  */
              EmacsView *view = FRAME_IOS_VIEW (f);
              if (view)
                {
                  dispatch_async (dispatch_get_main_queue (), ^{
                    view.backgroundColor = bgColor;
                    NSLog(@"ios_update_end: updated EmacsView backgroundColor to (%.2f,%.2f,%.2f)",
                          r, g, b);
                  });
                  /* Clear the offscreen buffer with the new background color.  */
                  [view clearOffscreenWithBackgroundColor];
                }
              
              /* Mark frame as needing full redisplay with new colors.  */
              SET_FRAME_GARBAGED (f);
            }
        }
    }
  
  /* Request a display update after Emacs finishes drawing.  */
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view)
    ios_request_display (view);
}

/* Flush pending display updates.  Called after redisplay is complete.  */
static void
ios_flush_display (struct frame *f)
{
  IOSTRACE ("ios_flush_display");
  
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view == nil)
    return;
  
  /* Ensure display updates happen on the main thread.  */
  ios_request_display (view);
}


/* ==========================================================================

   Event Queue (modeled after Android port)

   ========================================================================== */

#include <pthread.h>

/* Event container for the linked list queue.  */
struct ios_event_container
{
  struct ios_event_container *next;
  struct ios_event_container *last;
  union ios_event event;
};

/* The event queue structure.  */
static struct {
  pthread_mutex_t mutex;
  pthread_cond_t read_var;
  struct ios_event_container events;  /* Sentinel for circular list */
  int num_events;
  bool initialized;
} ios_event_queue;

/* Initialize the event queue.  Must be called before any events are posted.  */
static void
ios_init_event_queue (void)
{
  if (ios_event_queue.initialized)
    return;
  
  pthread_mutex_init (&ios_event_queue.mutex, NULL);
  pthread_cond_init (&ios_event_queue.read_var, NULL);
  
  /* Initialize the circular list with the sentinel pointing to itself.  */
  ios_event_queue.events.next = &ios_event_queue.events;
  ios_event_queue.events.last = &ios_event_queue.events;
  ios_event_queue.num_events = 0;
  ios_event_queue.initialized = true;
  
  NSLog(@"ios_init_event_queue: initialized");
}

/* Write an event to the queue.  Called from the main (UI) thread.  */
void
ios_write_event (union ios_event *event)
{
  struct ios_event_container *container;
  
  if (!ios_event_queue.initialized)
    {
      NSLog(@"ios_write_event: queue not initialized, dropping event type=%d", event->type);
      return;
    }
  
  container = malloc (sizeof *container);
  if (!container)
    {
      NSLog(@"ios_write_event: malloc failed");
      return;
    }
  
  pthread_mutex_lock (&ios_event_queue.mutex);
  
  /* Insert at the head of the list.  */
  container->next = ios_event_queue.events.next;
  container->last = &ios_event_queue.events;
  container->next->last = container;
  container->last->next = container;
  container->event = *event;
  ios_event_queue.num_events++;
  
  NSLog(@"ios_write_event: added event type=%d, queue now has %d events",
        event->type, ios_event_queue.num_events);
  
  /* Wake up the Emacs thread if it's waiting.  */
  pthread_cond_broadcast (&ios_event_queue.read_var);
  pthread_mutex_unlock (&ios_event_queue.mutex);
  
  /* Also set pending_signals and raise SIGIO for important events.  */
  pending_signals = true;
  if (event->type == IOS_KEY_DOWN || event->type == IOS_CONFIGURE_NOTIFY)
    {
      kill (getpid (), SIGIO);
    }
}

/* Check if events are pending.  */
int
ios_pending (void)
{
  int count;
  
  if (!ios_event_queue.initialized)
    return 0;
  
  pthread_mutex_lock (&ios_event_queue.mutex);
  count = ios_event_queue.num_events;
  pthread_mutex_unlock (&ios_event_queue.mutex);
  
  return count;
}

/* Wait for an event to become available.  */
void
ios_wait_event (void)
{
  if (!ios_event_queue.initialized)
    return;
  
  pthread_mutex_lock (&ios_event_queue.mutex);
  
  if (ios_event_queue.num_events == 0)
    {
      /* Wait with short timeout (5ms) for responsive input.  */
      struct timespec timeout;
      clock_gettime (CLOCK_REALTIME, &timeout);
      timeout.tv_nsec += 5 * 1000000;  /* 5ms timeout */
      if (timeout.tv_nsec >= 1000000000)
        {
          timeout.tv_sec++;
          timeout.tv_nsec -= 1000000000;
        }
      pthread_cond_timedwait (&ios_event_queue.read_var,
                              &ios_event_queue.mutex,
                              &timeout);
    }
  
  pthread_mutex_unlock (&ios_event_queue.mutex);
}

/* Get the next event from the queue.  Returns false if no events available.  */
bool
ios_next_event (union ios_event *event_return)
{
  struct ios_event_container *container;
  
  if (!ios_event_queue.initialized)
    return false;
  
  pthread_mutex_lock (&ios_event_queue.mutex);
  
  /* If no events, return immediately (non-blocking).  */
  if (ios_event_queue.num_events == 0)
    {
      pthread_mutex_unlock (&ios_event_queue.mutex);
      return false;
    }
  
  /* Get event from the tail (FIFO order).  */
  container = ios_event_queue.events.last;
  
  /* Remove from list.  */
  container->last->next = container->next;
  container->next->last = container->last;
  *event_return = container->event;
  ios_event_queue.num_events--;
  
  pthread_mutex_unlock (&ios_event_queue.mutex);
  
  NSLog(@"ios_next_event: got event type=%d, queue now has %d events",
        event_return->type, ios_event_queue.num_events);
  
  free (container);
  return true;
}


/* ==========================================================================

   Event reading (read_socket_hook)

   ========================================================================== */

/* Counter for events stored via kbd_buffer_store_event from the UI thread */
static volatile int ios_pending_event_count = 0;

/* Request a frame expose/redisplay from the main thread.
   This is called when layoutSublayersOfLayer: detects the frame is garbaged.
   The actual redisplay happens on the Emacs thread in ios_read_socket.  */
void
ios_request_expose (struct frame *f)
{
  union ios_event event;
  event.xexpose.type = IOS_EXPOSE;
  event.xexpose.frame = f;
  ios_write_event (&event);
}

/* Request a frame resize from the main thread.
   This queues a configure event for the Emacs thread to process.  */
void
ios_request_frame_resize (struct frame *f, int width, int height)
{
  union ios_event event;
  NSLog(@"ios_request_frame_resize: frame=%p %dx%d", f, width, height);
  event.xconfigure.type = IOS_CONFIGURE_NOTIFY;
  event.xconfigure.frame = f;
  event.xconfigure.width = width;
  event.xconfigure.height = height;
  ios_write_event (&event);
}

/* Signal that events are available - called from main thread when UIKit events arrive.
   This wakes up the Emacs thread if it's waiting and increments the legacy event count.  */
void
ios_signal_event_available (void)
{
  __sync_add_and_fetch (&ios_pending_event_count, 1);
  
  /* Wake up the event queue if initialized.  */
  if (ios_event_queue.initialized)
    {
      pthread_mutex_lock (&ios_event_queue.mutex);
      pthread_cond_broadcast (&ios_event_queue.read_var);
      pthread_mutex_unlock (&ios_event_queue.mutex);
    }
  
  /* Raise SIGIO to interrupt the Emacs thread if it's blocked in select/pselect.
     This is critical for responsive input - without it, Emacs may not notice
     new events until it naturally returns to the event loop.  */
  pending_signals = true;
  kill (getpid (), SIGIO);
}

/* Get drawing context for a frame - for use by macfont.m.
   This returns the offscreen buffer context if available.  */
CGContextRef
ios_frame_get_drawing_context (struct frame *f)
{
  if (!f || !FRAME_LIVE_P (f))
    return NULL;
    
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view)
    {
      CGContextRef ctx = [view getOffscreenContext];
      if (ctx)
        return ctx;
    }
  
  /* Fallback to UIGraphicsGetCurrentContext.  */
  return UIGraphicsGetCurrentContext ();
}

static int
ios_read_socket (struct terminal *terminal, struct input_event *hold_quit)
{
  static int call_count = 0;
  call_count++;
  
  /* Initialize the event queue on first call.  */
  static dispatch_once_t once;
  dispatch_once (&once, ^{
    ios_init_event_queue ();
  });

  int nevents = 0;
  
  /* Log every call to track if command loop is running.  */
  if (call_count <= 10 || call_count % 100 == 0)
    NSLog(@"ios_read_socket: call #%d, queue has %d events", call_count, ios_pending ());

  /* Process events from the iOS event queue (modeled after Android).  */
  block_input ();
  {
    union ios_event event;
    while (ios_next_event (&event))
      {
        switch (event.type)
          {
          case IOS_CONFIGURE_NOTIFY:
            {
              struct frame *f = event.xconfigure.frame;
            int width = event.xconfigure.width;
            int height = event.xconfigure.height;
            
            if (f && FRAME_LIVE_P (f)
                && (width != FRAME_PIXEL_WIDTH (f) || height != FRAME_PIXEL_HEIGHT (f)))
              {
                NSLog(@"ios_read_socket: processing CONFIGURE_NOTIFY %dx%d -> %dx%d",
                      FRAME_PIXEL_WIDTH (f), FRAME_PIXEL_HEIGHT (f), width, height);
                
                change_frame_size (f, width, height, false, true, false);
                SET_FRAME_GARBAGED (f);
                
                EmacsView *view = FRAME_IOS_VIEW (f);
                if (view)
                  ios_request_display (view);
                
                nevents++;
              }
          }
          break;
          
        case IOS_EXPOSE:
          {
            struct frame *f = event.xexpose.frame;
            
            if (f && FRAME_LIVE_P (f))
              {
                NSLog(@"ios_read_socket: processing EXPOSE for frame %p", f);
                
                if (FRAME_GARBAGED_P (f))
                  expose_frame (f, 0, 0, FRAME_PIXEL_WIDTH (f), FRAME_PIXEL_HEIGHT (f));
                
                EmacsView *view = FRAME_IOS_VIEW (f);
                if (view)
                  ios_request_display (view);
                
                nevents++;
              }
          }
          break;
          
        default:
          NSLog(@"ios_read_socket: unknown event type %d", event.type);
          break;
          }
      }
  }
  unblock_input ();

  /* Check if we have pending kbd events (stored directly via kbd_buffer_store_event).  */
  int pending = __sync_lock_test_and_set (&ios_pending_event_count, 0);
  if (pending > 0)
    {
      if (call_count <= 10 || call_count % 100 == 0)
        NSLog(@"ios_read_socket: returning %d kbd pending events", pending);
      return pending + nevents;
    }

  block_input ();

  /* Process any pending events from the hold queue.  */
  while (hold_event_q.nr > 0)
    {
      hold_event_q.nr--;
      kbd_buffer_store_event_hold (&hold_event_q.q[hold_event_q.nr], hold_quit);
      nevents++;
    }

  /* If we have events, return immediately */
  if (nevents > 0)
    {
      send_appdefined = YES;
      unblock_input ();
      return nevents;
    }

  unblock_input ();

  /* If we have any events (from queue or kbd), return immediately.  */
  if (nevents > 0)
    return nevents;

  /* No events yet - wait briefly for events to arrive.
     The wait is interruptible by SIGIO.  */
  ios_wait_event ();

  /* After waiting, check for new queue events.  */
  block_input ();
  {
    union ios_event event;
    while (ios_next_event (&event))
      {
        switch (event.type)
          {
          case IOS_CONFIGURE_NOTIFY:
            {
              struct frame *f = event.xconfigure.frame;
              int width = event.xconfigure.width;
              int height = event.xconfigure.height;
              
              if (f && FRAME_LIVE_P (f)
                  && (width != FRAME_PIXEL_WIDTH (f) || height != FRAME_PIXEL_HEIGHT (f)))
                {
                  change_frame_size (f, width, height, false, true, false);
                  SET_FRAME_GARBAGED (f);
                  EmacsView *view = FRAME_IOS_VIEW (f);
                  if (view)
                    ios_request_display (view);
                  nevents++;
                }
            }
            break;
            
          case IOS_EXPOSE:
            {
              struct frame *f = event.xexpose.frame;
              if (f && FRAME_LIVE_P (f) && FRAME_GARBAGED_P (f))
                {
                  expose_frame (f, 0, 0, FRAME_PIXEL_WIDTH (f), FRAME_PIXEL_HEIGHT (f));
                  EmacsView *view = FRAME_IOS_VIEW (f);
                  if (view)
                    ios_request_display (view);
                  nevents++;
                }
            }
            break;
            
          default:
            break;
          }
      }
  }
  unblock_input ();

  /* Check kbd pending events again after waiting */
  pending = __sync_lock_test_and_set (&ios_pending_event_count, 0);
  nevents += pending;

  /* Check for events in hold queue after waiting */
  block_input ();
  while (hold_event_q.nr > 0)
    {
      hold_event_q.nr--;
      kbd_buffer_store_event_hold (&hold_event_q.q[hold_event_q.nr], hold_quit);
      nevents++;
    }

  send_appdefined = YES;
  unblock_input ();

  return nevents;
}


/* ==========================================================================

   Color handling

   ========================================================================== */

bool
ios_defined_color (struct frame *f, const char *name,
                   Emacs_Color *color_def, bool alloc, bool makeIndex)
{
  static int color_debug_count = 0;
  color_debug_count++;
  
  /* Log font-lock related colors (purple, cyan, blue, green, red, etc.) */
  bool log_this_color = (strcasecmp(name, "purple") == 0 ||
                         strcasecmp(name, "cyan") == 0 ||
                         strcasecmp(name, "cyan1") == 0 ||
                         strcasecmp(name, "blue") == 0 ||
                         strcasecmp(name, "red") == 0 ||
                         strcasecmp(name, "green") == 0 ||
                         strcasecmp(name, "chocolate") == 0 ||
                         strcasecmp(name, "darkgoldenrod") == 0 ||
                         strcasecmp(name, "firebrick") == 0 ||
                         strcasecmp(name, "orchid") == 0 ||
                         strcasecmp(name, "darkorange") == 0 ||
                         strstr(name, "purple") != NULL ||
                         strstr(name, "Purple") != NULL ||
                         strstr(name, "cyan") != NULL ||
                         strstr(name, "Cyan") != NULL);
  
  unsigned short r, g, b;

  /* First try parse_color_spec for #RGB, rgb:, etc. formats.  */
  if (parse_color_spec (name, &r, &g, &b))
    {
      color_def->red = r;
      color_def->green = g;
      color_def->blue = b;
      color_def->pixel = RGB_TO_ULONG (r >> 8, g >> 8, b >> 8);
      if (color_debug_count <= 30 || log_this_color)
        NSLog(@"ios_defined_color: '%s' -> parse_color_spec: pixel=0x%lx", name, color_def->pixel);
      return true;
    }

  /* Look up in color map loaded from rgb.txt.  */
  struct ios_display_info *dpyinfo = FRAME_DISPLAY_INFO (f);
  if (!dpyinfo)
    {
      if (color_debug_count <= 30 || log_this_color)
        NSLog(@"ios_defined_color: '%s' -> NO DPYINFO!", name);
      return false;
    }
  
  Lisp_Object tem = dpyinfo->color_map;
  if (NILP (tem))
    {
      if (color_debug_count <= 30 || log_this_color)
        NSLog(@"ios_defined_color: '%s' -> color_map is nil!", name);
      return false;
    }
  
  int loop_count = 0;
  for (; CONSP (tem); tem = XCDR (tem))
    {
      Lisp_Object tem1 = XCAR (tem);
      loop_count++;

      if (CONSP (tem1) && STRINGP (XCAR (tem1)))
        {
          const char *entry_name = SSDATA (XCAR (tem1));
          if (!strcasecmp (entry_name, name))
            {
              unsigned long lisp_color = XFIXNUM (XCDR (tem1));
              color_def->red = RED_FROM_ULONG (lisp_color) * 257;
              color_def->green = GREEN_FROM_ULONG (lisp_color) * 257;
              color_def->blue = BLUE_FROM_ULONG (lisp_color) * 257;
              color_def->pixel = lisp_color;
              if (color_debug_count <= 30 || log_this_color)
                NSLog(@"ios_defined_color: '%s' -> found in color_map at entry %d: pixel=0x%lx", name, loop_count, color_def->pixel);
              return true;
            }
        }
    }

  if (color_debug_count <= 30 || log_this_color)
    NSLog(@"ios_defined_color: '%s' -> NOT FOUND (searched %d entries)", name, loop_count);
  return false;
}

static void
ios_query_frame_background_color (struct frame *f, Emacs_Color *bgcolor)
{
  IOSTRACE ("ios_query_frame_background_color");

  struct ios_output *output = f->output_data.ios;
  if (output && output->background_color)
    {
      CGFloat r, g, b, a;
      [output->background_color getRed:&r green:&g blue:&b alpha:&a];
      bgcolor->red = (unsigned int)(r * 65535);
      bgcolor->green = (unsigned int)(g * 65535);
      bgcolor->blue = (unsigned int)(b * 65535);
      bgcolor->pixel = RGB_TO_ULONG ((int)(r * 255), (int)(g * 255), (int)(b * 255));
    }
}

unsigned long
ios_get_rgb_color (struct frame *f, float r, float g, float b, float a)
{
  return (((unsigned long)(a * 255) << 24)
          | ((unsigned long)(r * 255) << 16)
          | ((unsigned long)(g * 255) << 8)
          | (unsigned long)(b * 255));
}


/* ==========================================================================

   Frame parameters

   ========================================================================== */

void
ios_implicitly_set_name (struct frame *f, Lisp_Object arg, Lisp_Object oldval)
{
  IOSTRACE ("ios_implicitly_set_name");

  /* On iOS, we don't have a title bar, but we track the name anyway.  */
  if (NILP (arg))
    arg = build_string ("Emacs");

  fset_name (f, arg);
}

static void
ios_frame_raise_lower (struct frame *f, bool raise_flag)
{
  /* On iOS, apps can't directly control their z-order.
     This is handled by the system.  */
  IOSTRACE ("ios_frame_raise_lower (limited on iOS)");
}


/* ==========================================================================

   Resources and defaults

   ========================================================================== */

const char *
ios_get_string_resource (void *_rdb, const char *name, const char *class)
{
  /* iOS uses NSUserDefaults instead of X resources.  */
  return ios_get_defaults_value (name);
}

const char *
ios_get_defaults_value (const char *key)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *nsKey = [NSString stringWithUTF8String:key];
  NSString *value = [defaults stringForKey:nsKey];
  return value ? [value UTF8String] : NULL;
}


/* ==========================================================================

   Cursor (no-op on iOS, but needed for compatibility)

   ========================================================================== */

static void
ios_define_frame_cursor (struct frame *f, Emacs_Cursor cursor)
{
  /* iOS doesn't have mouse cursors.  */
}


/* ==========================================================================

   Cleanup

   ========================================================================== */

static void
ios_free_pixmap (struct frame *f, Emacs_Pixmap pixmap)
{
  /* Release a pixmap.  */
  if (pixmap)
    [(id)pixmap release];
}

static void
ios_destroy_window (struct frame *f)
{
  IOSTRACE ("ios_destroy_window");
  ios_free_frame_resources (f);
}

void
ios_free_frame_resources (struct frame *f)
{
  IOSTRACE ("ios_free_frame_resources");

  struct ios_output *output = f->output_data.ios;
  if (!output)
    return;

  block_input ();

  /* Release colors.  */
  if (output->cursor_color)
    [output->cursor_color release];
  if (output->foreground_color)
    [output->foreground_color release];
  if (output->background_color)
    [output->background_color release];

  /* Release view.  */
  if (output->view)
    {
      [output->view removeFromSuperview];
      [output->view release];
    }

  /* Release view controller.  */
  if (output->viewController)
    [output->viewController release];

  /* Free touch points.  */
  struct ios_touch_point *tp = output->touch_points;
  while (tp)
    {
      struct ios_touch_point *next = tp->next;
      xfree (tp);
      tp = next;
    }

  xfree (output);
  f->output_data.ios = NULL;

  unblock_input ();
}

static void
ios_delete_terminal (struct terminal *terminal)
{
  IOSTRACE ("ios_delete_terminal");

  struct ios_display_info *dpyinfo = terminal->display_info.ios;

  /* Protect against recursive calls.  */
  if (!terminal->name)
    return;

  block_input ();

  image_destroy_all_bitmaps (dpyinfo);

  /* Free display info.  */
  xfree (dpyinfo);

  unblock_input ();
}


/* ==========================================================================

   Font handling

   ========================================================================== */

/* Set the font of frame F to the font object FONT_OBJECT.
   Return FONT_OBJECT.  */
static Lisp_Object
ios_new_font (struct frame *f, Lisp_Object font_object, int fontset)
{
  struct font *font = XFONT_OBJECT (font_object);
  EmacsView *view = FRAME_IOS_VIEW (f);
  int font_ascent, font_descent;

  if (fontset < 0)
    fontset = fontset_from_font (font_object);
  FRAME_FONTSET (f) = fontset;

  if (FRAME_FONT (f) == font)
    /* This font is already set in frame F.  There's nothing more to
       do.  */
    return font_object;

  FRAME_FONT (f) = font;

  FRAME_BASELINE_OFFSET (f) = font->baseline_offset;
  FRAME_COLUMN_WIDTH (f) = font->average_width;
  get_font_ascent_descent (font, &font_ascent, &font_descent);
  FRAME_LINE_HEIGHT (f) = font_ascent + font_descent;

  /* Compute the scroll bar width in character columns.  */
  if (FRAME_CONFIG_SCROLL_BAR_WIDTH (f) > 0)
    {
      int wid = FRAME_COLUMN_WIDTH (f);
      FRAME_CONFIG_SCROLL_BAR_COLS (f)
        = (FRAME_CONFIG_SCROLL_BAR_WIDTH (f) + wid - 1) / wid;
    }
  else
    {
      int wid = FRAME_COLUMN_WIDTH (f);
      FRAME_CONFIG_SCROLL_BAR_COLS (f) = (14 + wid - 1) / wid;
    }

  /* Compute the scroll bar height in character lines.  */
  if (FRAME_CONFIG_SCROLL_BAR_HEIGHT (f) > 0)
    {
      int height = FRAME_LINE_HEIGHT (f);
      FRAME_CONFIG_SCROLL_BAR_LINES (f)
        = (FRAME_CONFIG_SCROLL_BAR_HEIGHT (f) + height - 1) / height;
    }
  else
    {
      int height = FRAME_LINE_HEIGHT (f);
      FRAME_CONFIG_SCROLL_BAR_LINES (f) = (14 + height - 1) / height;
    }

  /* Now make the frame display the given font.  On iOS, we don't need
     to adjust frame size here as frames are typically fullscreen.  */
  if (view != nil)
    {
      /* Request a redraw on the main thread.  */
      ios_request_display (view);
    }

  return font_object;
}


/* ==========================================================================

   Redisplay interface

   ========================================================================== */

/* Forward declarations for drawing functions.  */
static CGContextRef ios_get_drawing_context (struct frame *f);
static void ios_draw_glyph_string (struct glyph_string *s);
static void ios_draw_fringe_bitmap (struct window *w, struct glyph_row *row,
                                    struct draw_fringe_bitmap_params *p);
static void ios_draw_window_cursor (struct window *w, struct glyph_row *glyph_row,
                                    int x, int y,
                                    enum text_cursor_kinds cursor_type,
                                    int cursor_width, bool on_p, bool active_p);
static void ios_draw_vertical_window_border (struct window *w, int x, int y0, int y1);
static void ios_draw_window_divider (struct window *w, int x0, int x1, int y0, int y1);
static void ios_shift_glyphs_for_insert (struct frame *f, int x, int y,
                                         int width, int height, int shift_by);
static void ios_show_hourglass (struct frame *f);
static void ios_hide_hourglass (struct frame *f);
static void ios_default_font_parameter (struct frame *f, Lisp_Object parms);
static void ios_after_update_window_line (struct window *w, struct glyph_row *row);
static void ios_scroll_run (struct window *w, struct run *run);
static void ios_compute_glyph_string_overhangs (struct glyph_string *s);
static void ios_draw_vertical_window_border (struct window *w, int x, int y0, int y1);
static void ios_define_fringe_bitmap (int which, unsigned short *bits,
                                      int h, int wd);
static void ios_destroy_fringe_bitmap (int which);
static void ios_clear_under_internal_border (struct frame *f);

static struct redisplay_interface ios_redisplay_interface =
{
  ios_frame_parm_handlers,
  gui_produce_glyphs,
  gui_write_glyphs,
  gui_insert_glyphs,
  gui_clear_end_of_line,
  ios_scroll_run,
  ios_after_update_window_line,
  NULL, /* update_window_begin */
  NULL, /* update_window_end */
  ios_flush_display, /* flush_display */
  gui_clear_window_mouse_face,
  gui_get_glyph_overhangs,
  gui_fix_overlapping_area,
  ios_draw_fringe_bitmap,
  ios_define_fringe_bitmap,
  ios_destroy_fringe_bitmap,
  ios_compute_glyph_string_overhangs,
  ios_draw_glyph_string,
  ios_define_frame_cursor,
  ios_clear_frame_area,
  ios_clear_under_internal_border,
  ios_draw_window_cursor,
  ios_draw_vertical_window_border,
  ios_draw_window_divider,
  ios_shift_glyphs_for_insert,
  ios_show_hourglass,
  ios_hide_hourglass,
  ios_default_font_parameter
};


/* ==========================================================================

   Drawing implementation

   ========================================================================== */

/* Get the graphics context for drawing.  
   ALWAYS uses the offscreen buffer when it exists. This ensures all Emacs
   drawing goes to the offscreen buffer, and drawRect just blits it to screen.  */
static CGContextRef
ios_get_drawing_context (struct frame *f)
{
  /* ALWAYS prefer the offscreen buffer for consistent drawing.  */
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view)
    {
      CGContextRef ctx = [view getOffscreenContext];
      if (ctx)
        return ctx;
    }
  
  /* Fallback to UIGraphicsGetCurrentContext (only during initial setup).  */
  return UIGraphicsGetCurrentContext ();
}

/* Get foreground color for glyph string.  */
static UIColor *
ios_get_foreground_color (struct glyph_string *s)
{
  if (s->hl == DRAW_CURSOR)
    return [UIColor colorWithUnsignedLong:s->face->foreground];
  else
    return [UIColor colorWithUnsignedLong:s->face->foreground];
}

/* Get background color for glyph string.  */
static UIColor *
ios_get_background_color (struct glyph_string *s)
{
  if (s->hl == DRAW_CURSOR)
    return FRAME_CURSOR_COLOR (s->f);
  else
    return [UIColor colorWithUnsignedLong:s->face->background];
}

/* Draw glyph string foreground using font driver.  */
static void
ios_draw_glyph_string_foreground (struct glyph_string *s)
{
  int x;
  struct font *font = s->font;

  /* If first glyph has a left box line, offset the text.  */
  if (s->face && s->face->box != FACE_NO_BOX
      && s->first_glyph->left_box_line_p)
    x = s->x + max (s->face->box_vertical_line_width, 0);
  else
    x = s->x;

  /* Draw using font driver.  The background_filled_p flag is always true
     after ios_maybe_dumpglyphs_background, so with_background is false.  */
  if (font && font->driver && font->driver->draw)
    font->driver->draw (s, s->cmp_from, s->nchars, x, s->ybase,
                        !s->for_overlaps && !s->background_filled_p);
}

/* Maybe fill background for glyph string.  */
static void
ios_maybe_dumpglyphs_background (struct glyph_string *s, bool force_p)
{
  /* On iOS we use an offscreen bitmap that persists between frames.
     Unlike the NS port where the system may clear the view, we MUST
     always fill the background to avoid ghosting from old text.  */
  
  if (!s->background_filled_p)
    {
      int box_line_width = max (s->face->box_horizontal_line_width, 0);
      
      /* Always fill background on iOS - our offscreen buffer persists.  */
      CGContextRef context = ios_get_drawing_context (s->f);

      if (context)
        {
          UIColor *bgColor = ios_get_background_color (s);
          int y = s->y + box_line_width;
          int h = s->height - 2 * box_line_width;
          CGFloat cg_y = ios_cg_y_for_emacs_y (s->f, y, h);
          CGContextSetFillColorWithColor (context, bgColor.CGColor);
          CGContextFillRect (context, CGRectMake (s->x, cg_y,
                                                  s->background_width, h));
        }
      s->background_filled_p = true;
    }
}

/* Draw text decorations: underline, overline, strike-through.  */
static void
ios_draw_text_decoration (struct glyph_string *s)
{
  if (s->for_overlaps)
    return;

  struct face *face = s->face;
  CGContextRef context = ios_get_drawing_context (s->f);
  if (!context)
    return;

  CGFloat x = s->x;
  CGFloat width = s->width;

  /* Draw underline.  */
  if (face->underline && face->underline != FACE_NO_UNDERLINE)
    {
      unsigned long color = face->underline_defaulted_p
        ? face->foreground : face->underline_color;
      UIColor *underlineColor = [UIColor colorWithUnsignedLong:color];
      CGContextSetStrokeColorWithColor (context, underlineColor.CGColor);

      /* Calculate underline position and thickness.  */
      struct font *font = s->font;
      CGFloat thickness = (font && font->underline_thickness > 0)
        ? font->underline_thickness : 1.0;
      CGFloat position = (font && font->underline_position >= 0)
        ? font->underline_position : (font ? font->descent / 2 : 2);

      CGFloat y = s->ybase + position;

      CGContextSetLineWidth (context, thickness);

      if (face->underline == FACE_UNDERLINE_WAVE)
        {
          /* Draw wavy underline.  */
          CGFloat wave_height = 2.0;
          CGFloat wave_length = 4.0;
          CGContextBeginPath (context);
          CGContextMoveToPoint (context, x, y);
          for (CGFloat wx = x; wx < x + width; wx += wave_length)
            {
              CGFloat wy = (int)((wx - x) / wave_length) % 2 == 0
                ? y - wave_height : y + wave_height;
              CGContextAddLineToPoint (context, wx + wave_length/2, wy);
            }
          CGContextStrokePath (context);
        }
      else
        {
          /* Draw straight line (single, double, dots, dashes).  */
          if (face->underline == FACE_UNDERLINE_DASHES)
            {
              CGFloat dash[] = { 3.0, 3.0 };
              CGContextSetLineDash (context, 0, dash, 2);
            }
          else if (face->underline == FACE_UNDERLINE_DOTS)
            {
              CGFloat dots[] = { 1.0, 2.0 };
              CGContextSetLineDash (context, 0, dots, 2);
            }

          CGContextMoveToPoint (context, x, y + 0.5);
          CGContextAddLineToPoint (context, x + width, y + 0.5);
          CGContextStrokePath (context);

          /* Reset dash pattern.  */
          CGContextSetLineDash (context, 0, NULL, 0);
        }
    }

  /* Draw overline.  */
  if (face->overline_p)
    {
      unsigned long color = face->overline_color_defaulted_p
        ? face->foreground : face->overline_color;
      UIColor *overlineColor = [UIColor colorWithUnsignedLong:color];
      CGContextSetStrokeColorWithColor (context, overlineColor.CGColor);
      CGContextSetLineWidth (context, 1.0);

      CGFloat y = s->y + 0.5;
      CGContextMoveToPoint (context, x, y);
      CGContextAddLineToPoint (context, x + width, y);
      CGContextStrokePath (context);
    }

  /* Draw strike-through.  */
  if (face->strike_through_p)
    {
      unsigned long color = face->strike_through_color_defaulted_p
        ? face->foreground : face->strike_through_color;
      UIColor *strikeColor = [UIColor colorWithUnsignedLong:color];
      CGContextSetStrokeColorWithColor (context, strikeColor.CGColor);
      CGContextSetLineWidth (context, 1.0);

      /* Strike through the middle of the text.  */
      struct font *font = s->font;
      CGFloat y = s->ybase - (font ? font->ascent / 2 : s->height / 4) + 0.5;
      CGContextMoveToPoint (context, x, y);
      CGContextAddLineToPoint (context, x + width, y);
      CGContextStrokePath (context);
    }
}

/* Clipping support - modeled after NS port's ns_focus/ns_unfocus.  */
static bool ios_clip_saved = false;

static int
ios_get_glyph_string_clip_rect (struct glyph_string *s, CGRect *r)
{
  /* Use the standard Emacs function to compute clip rects.
     NativeRectangle is CGRect on iOS (defined in iosgui.h).  */
  CGRect nr[2];
  int n = get_glyph_string_clip_rects (s, nr, 2);
  
  /* Convert Y coordinates from Emacs (top=0) to CoreGraphics (bottom=0).  */
  for (int i = 0; i < n; i++)
    {
      CGFloat cg_y = ios_cg_y_for_emacs_y (s->f, (int)nr[i].origin.y, (int)nr[i].size.height);
      r[i] = CGRectMake (nr[i].origin.x, cg_y, nr[i].size.width, nr[i].size.height);
    }
  return n;
}

static void
ios_focus (struct frame *f, CGRect *r, int n)
{
  /* Set up clipping for the drawing region.  */
  CGContextRef context = ios_get_drawing_context (f);
  if (!context || !r)
    return;
    
  CGContextSaveGState (context);
  ios_clip_saved = true;
  
  if (n == 1)
    CGContextClipToRect (context, r[0]);
  else if (n == 2)
    CGContextClipToRects (context, r, 2);
}

static void
ios_unfocus (struct frame *f)
{
  if (ios_clip_saved)
    {
      CGContextRef context = ios_get_drawing_context (f);
      if (context)
        CGContextRestoreGState (context);
      ios_clip_saved = false;
    }
}

static void
ios_draw_glyph_string (struct glyph_string *s)
{
  /* Debug: log face colors for font-lock debugging */
  static int draw_count = 0;
  draw_count++;
  /* Log first 200 glyphs and any with non-zero foreground to debug font-lock */
  if (draw_count <= 200 || (s->face && s->face->foreground != 0))
    {
      NSLog(@"ios_draw_glyph_string[%d]: face_id=%d fg=0x%lx bg=0x%lx nchars=%d type=%d",
            draw_count, s->face ? s->face->id : -1,
            s->face ? s->face->foreground : 0,
            s->face ? s->face->background : 0,
            s->nchars, s->first_glyph ? s->first_glyph->type : -1);
    }
  
  IOSTRACE ("ios_draw_glyph_string: type=%d x=%d y=%d w=%d nchars=%d",
            s->first_glyph->type, s->x, s->y, s->width, s->nchars);

  /* Modeled after ns_draw_glyph_string in nsterm.m */
  CGRect r[2];
  int n;
  struct font *font = s->face->font;
  if (!font)
    font = FRAME_FONT (s->f);

  /* Mark that offscreen buffer has content when we draw.  */
  EmacsView *view = FRAME_IOS_VIEW (s->f);
  if (view)
    [view markOffscreenHasContent];

  /* Handle right overhang - draw background for overlapping strings.
     This matches ns_draw_glyph_string behavior.  */
  if (s->next && s->right_overhang && !s->for_overlaps)
    {
      int width;
      struct glyph_string *next;

      for (width = 0, next = s->next;
           next && width < s->right_overhang;
           width += next->width, next = next->next)
        {
          if (next->first_glyph->type != IMAGE_GLYPH)
            {
              n = ios_get_glyph_string_clip_rect (next, r);
              ios_focus (s->f, r, n);
              if (next->first_glyph->type != STRETCH_GLYPH)
                ios_maybe_dumpglyphs_background (next, true);
              ios_unfocus (s->f);
            }
        }
    }

  /* Get clip rect for this glyph string.  */
  n = ios_get_glyph_string_clip_rect (s, r);

  /* Restrict clip rect if there are overhangs and no explicit clip.  */
  if (!s->clip_head && !s->clip_tail
      && ((s->prev && s->prev->hl != s->hl && s->left_overhang)
          || (s->next && s->next->hl != s->hl && s->right_overhang)))
    {
      CGFloat cg_y = ios_cg_y_for_emacs_y (s->f, s->y, s->height);
      CGRect sRect = CGRectMake (s->x, cg_y, s->width, s->height);
      r[0] = CGRectIntersection (r[0], sRect);
    }

  /* Focus with clipping.  */
  ios_focus (s->f, r, n);

  switch (s->first_glyph->type)
    {
    case IMAGE_GLYPH:
      /* TODO: Implement image drawing.  */
      break;

    case STRETCH_GLYPH:
      /* Draw stretch glyph (empty space).  */
      {
        CGContextRef context = ios_get_drawing_context (s->f);
        if (context)
          {
            UIColor *bgColor = ios_get_background_color (s);
            CGFloat cg_y = ios_cg_y_for_emacs_y (s->f, s->y, s->height);
            CGContextSetFillColorWithColor (context, bgColor.CGColor);
            CGContextFillRect (context, CGRectMake (s->x, cg_y,
                                                    s->width, s->height));
          }
        s->background_filled_p = true;
      }
      break;

    case CHAR_GLYPH:
    case COMPOSITE_GLYPH:
      {
        bool isComposite = s->first_glyph->type == COMPOSITE_GLYPH;
        
        /* Handle background fill.  */
        if (s->for_overlaps || (isComposite
                                && (s->cmp_from > 0
                                    && !s->first_glyph->u.cmp.automatic)))
          s->background_filled_p = true;
        else
          ios_maybe_dumpglyphs_background (s, isComposite);

        /* Draw foreground text.  */
        ios_draw_glyph_string_foreground (s);

        /* Draw underline, overline, strike-through.  */
        ios_draw_text_decoration (s);
      }
      break;

    case GLYPHLESS_GLYPH:
      if (s->for_overlaps || (s->cmp_from > 0
                              && !s->first_glyph->u.cmp.automatic))
        s->background_filled_p = true;
      else
        ios_maybe_dumpglyphs_background (s, false);
      /* Draw hex code or acronym for glyphless characters.  */
      {
        CGContextRef context = ios_get_drawing_context (s->f);
        if (context && s->font)
          {
            /* Draw a simple box to indicate glyphless char.  */
            UIColor *fgColor = ios_get_foreground_color (s);
            CGFloat cg_y = ios_cg_y_for_emacs_y (s->f, s->y, s->height);
            CGContextSetStrokeColorWithColor (context, fgColor.CGColor);
            CGContextSetLineWidth (context, 1.0);
            CGContextStrokeRect (context, CGRectMake (s->x + 1, cg_y + 1,
                                                      s->width - 2,
                                                      s->height - 2));
          }
      }
      break;

    default:
      break;
    }

  /* Remove clipping.  */
  ios_unfocus (s->f);
}

static void
ios_draw_fringe_bitmap (struct window *w, struct glyph_row *row,
                        struct draw_fringe_bitmap_params *p)
{
  struct frame *f = XFRAME (WINDOW_FRAME (w));
  struct face *face = p->face;

  IOSTRACE ("ios_draw_fringe_bitmap: which=%d cursor=%d overlay=%d",
            p->which, p->cursor_p, p->overlay_p);

  CGContextRef context = ios_get_drawing_context (f);
  if (!context)
    return;

  /* Calculate the rectangle to clear/draw.  Convert to CG coords.  */
  CGFloat cg_y = ios_cg_y_for_emacs_y (f, p->y, p->h);
  CGRect bmpRect = CGRectMake (p->x, cg_y, p->wd, p->h);

  /* Extend rect if background area is specified.  */
  if (p->bx >= 0)
    {
      CGFloat bg_cg_y = ios_cg_y_for_emacs_y (f, p->by, p->ny);
      bmpRect = CGRectUnion (bmpRect, CGRectMake (p->bx, bg_cg_y, p->nx, p->ny));
    }

  /* Clear the fringe background unless overlay.  */
  if (!p->overlay_p)
    {
      UIColor *bgColor = [UIColor colorWithUnsignedLong:face->background];
      CGContextSetFillColorWithColor (context, bgColor.CGColor);
      CGContextFillRect (context, bmpRect);
    }

  /* Draw the fringe bitmap if there is one.  */
  if (p->which > 0)
    {
      /* Get the appropriate color.  */
      UIColor *fgColor;
      if (p->cursor_p)
        fgColor = FRAME_CURSOR_COLOR (f);
      else
        fgColor = [UIColor colorWithUnsignedLong:face->foreground];

      CGContextSetFillColorWithColor (context, fgColor.CGColor);

      /* Draw a simple representation of the fringe indicator.
         The actual bitmap data is in fringe.c but not exported.
         For now, draw generic indicators based on position.  */
      if (p->wd > 0 && p->h > 0)
        {
          /* Draw a small filled indicator.  Most fringe bitmaps
             are visual hints - arrows, angles, etc.  */
          CGFloat midY = cg_y + p->h / 2.0;
          CGFloat size = MIN (p->wd, 6);

          /* Draw a simple triangle/arrow shape.  */
          CGContextBeginPath (context);
          CGContextMoveToPoint (context, p->x, midY - size/2);
          CGContextAddLineToPoint (context, p->x + size, midY);
          CGContextAddLineToPoint (context, p->x, midY + size/2);
          CGContextClosePath (context);
          CGContextFillPath (context);
        }
    }
}

static void
ios_draw_window_cursor (struct window *w, struct glyph_row *glyph_row,
                        int x, int y,
                        enum text_cursor_kinds cursor_type,
                        int cursor_width, bool on_p, bool active_p)
{
  struct frame *f = WINDOW_XFRAME (w);
  struct glyph *phys_cursor_glyph;
  int fx, fy, h, cursor_height;

  NSLog(@"ios_draw_window_cursor: type=%d on=%d active=%d x=%d y=%d",
            cursor_type, on_p, active_p, x, y);

  if (!on_p)
    return;

  w->phys_cursor_type = cursor_type;
  w->phys_cursor_on_p = on_p;

  if (cursor_type == NO_CURSOR)
    {
      w->phys_cursor_width = 0;
      return;
    }

  if ((phys_cursor_glyph = get_phys_cursor_glyph (w)) == NULL)
    {
      IOSTRACE ("  No phys cursor glyph found");
      if (glyph_row->exact_window_width_line_p
          && w->phys_cursor.hpos >= glyph_row->used[TEXT_AREA])
        {
          glyph_row->cursor_in_fringe_p = 1;
          draw_fringe_bitmap (w, glyph_row, 0);
        }
      return;
    }

  get_phys_cursor_geometry (w, glyph_row, phys_cursor_glyph, &fx, &fy, &h);

  /* Adjust width for bar cursors.  */
  if (cursor_type == BAR_CURSOR)
    {
      if (cursor_width < 1)
        cursor_width = max (FRAME_CURSOR_WIDTH (f), 1);
      if (cursor_width < w->phys_cursor_width)
        w->phys_cursor_width = cursor_width;

      /* If the character under cursor is R2L, draw on the right.  */
      struct glyph *cursor_glyph = get_phys_cursor_glyph (w);
      if (cursor_glyph && (cursor_glyph->resolved_level & 1) != 0)
        fx += cursor_glyph->pixel_width - w->phys_cursor_width;
    }
  else if (cursor_type == HBAR_CURSOR)
    {
      cursor_height = (cursor_width < 1) ? lrint (0.25 * h) : cursor_width;
      if (cursor_height > glyph_row->height)
        cursor_height = glyph_row->height;
      if (h > cursor_height)
        fy += h - cursor_height;
      h = cursor_height;
    }

  /* Transform Y coordinate for CoreGraphics (Y=0 at bottom).  */
  CGFloat cg_fy = ios_cg_y_for_emacs_y (f, fy, h);
  CGRect r = CGRectMake (fx, cg_fy, w->phys_cursor_width, h);

  /* Clip to the text area.  Also convert text area Y.  */
  int text_y = WINDOW_TO_FRAME_PIXEL_Y (w, glyph_row->y);
  int text_h = glyph_row->visible_height;
  CGFloat cg_text_y = ios_cg_y_for_emacs_y (f, text_y, text_h);
  CGRect textAreaRect = CGRectMake (
    WINDOW_TEXT_TO_FRAME_PIXEL_X (w, 0),
    cg_text_y,
    window_box_width (w, TEXT_AREA),
    text_h);
  r = CGRectIntersection (r, textAreaRect);

  if (CGRectIsEmpty (r))
    return;

  CGContextRef context = ios_get_drawing_context (f);
  if (!context)
    return;

  CGContextSaveGState (context);
  CGContextClipToRect (context, r);

  UIColor *cursorColor = FRAME_CURSOR_COLOR (f);
  CGContextSetFillColorWithColor (context, cursorColor.CGColor);
  CGContextSetStrokeColorWithColor (context, cursorColor.CGColor);

  switch (cursor_type)
    {
    case DEFAULT_CURSOR:
    case NO_CURSOR:
      break;

    case FILLED_BOX_CURSOR:
      /* Draw the character under the cursor with cursor colors.  */
      draw_phys_cursor_glyph (w, glyph_row, DRAW_CURSOR);
      break;

    case HOLLOW_BOX_CURSOR:
      /* Draw a hollow rectangle.  */
      CGContextSetLineWidth (context, 1.0);
      CGContextStrokeRect (context, CGRectInset (r, 0.5, 0.5));
      break;

    case BAR_CURSOR:
    case HBAR_CURSOR:
      /* Draw a filled bar.  */
      CGContextFillRect (context, r);
      break;
    }

  CGContextRestoreGState (context);
}

static void
ios_draw_vertical_window_border (struct window *w, int x, int y0, int y1)
{
  struct frame *f = XFRAME (w->frame);

  IOSTRACE ("ios_draw_vertical_window_border: x=%d y0=%d y1=%d", x, y0, y1);

  CGContextRef context = ios_get_drawing_context (f);
  if (!context)
    return;

  struct face *face = FRAME_DEFAULT_FACE (f);
  UIColor *borderColor = [UIColor colorWithUnsignedLong:face->foreground];

  /* Convert Y coordinates for CG (Y=0 at bottom).  */
  CGFloat cg_y0 = ios_cg_y_for_emacs_point (f, y0);
  CGFloat cg_y1 = ios_cg_y_for_emacs_point (f, y1);
  
  CGContextSetStrokeColorWithColor (context, borderColor.CGColor);
  CGContextSetLineWidth (context, 1.0);
  CGContextMoveToPoint (context, x + 0.5, cg_y0);
  CGContextAddLineToPoint (context, x + 0.5, cg_y1);
  CGContextStrokePath (context);
}

static void
ios_draw_window_divider (struct window *w, int x0, int x1, int y0, int y1)
{
  struct frame *f = XFRAME (w->frame);

  IOSTRACE ("ios_draw_window_divider: x0=%d x1=%d y0=%d y1=%d", x0, x1, y0, y1);

  CGContextRef context = ios_get_drawing_context (f);
  if (!context)
    return;

  /* Get divider color - use window divider face if available.  */
  unsigned long color = FRAME_FOREGROUND_PIXEL (f);
  struct face *face = FACE_FROM_ID (f, WINDOW_DIVIDER_FACE_ID);
  if (face)
    color = face->foreground;

  /* Convert Y coordinates.  */
  int height = y1 - y0;
  CGFloat cg_y = ios_cg_y_for_emacs_y (f, y0, height);
  
  UIColor *dividerColor = [UIColor colorWithUnsignedLong:color];
  CGContextSetFillColorWithColor (context, dividerColor.CGColor);
  CGContextFillRect (context, CGRectMake (x0, cg_y, x1 - x0, height));
}

static void
ios_shift_glyphs_for_insert (struct frame *f, int x, int y,
                             int width, int height, int shift_by)
{
  IOSTRACE ("ios_shift_glyphs_for_insert: x=%d y=%d w=%d h=%d shift=%d",
            x, y, width, height, shift_by);

  /* On iOS, we don't do hardware scrolling.  The redisplay code
     will simply redraw the affected area.  Mark it for redisplay.  */
  EmacsView *view = FRAME_IOS_VIEW (f);
  if (view)
    {
      /* Convert to CG coordinates for the rect.  */
      CGFloat cg_y = ios_cg_y_for_emacs_y (f, y, height);
      CGRect rect = CGRectMake (x, cg_y, width + abs (shift_by), height);
      ios_request_display_rect (view, rect);
    }
}

static void
ios_show_hourglass (struct frame *f)
{
  IOSTRACE ("ios_show_hourglass");
  /* TODO: Show activity indicator.  */
}

static void
ios_hide_hourglass (struct frame *f)
{
  IOSTRACE ("ios_hide_hourglass");
  /* TODO: Hide activity indicator.  */
}

static void
ios_default_font_parameter (struct frame *f, Lisp_Object parms)
{
  /* Font handling is done via macfont backend.  */
}

static void
ios_after_update_window_line (struct window *w, struct glyph_row *row)
{
  IOSTRACE ("ios_after_update_window_line");
  
  /* Mark fringe bitmaps for redraw if this is a regular text line.  */
  if (!row->mode_line_p && !w->pseudo_window_p)
    row->redraw_fringe_bitmaps_p = true;
}

static void
ios_scroll_run (struct window *w, struct run *run)
{
  struct frame *f = XFRAME (w->frame);
  int x, y, width, height, from_y, to_y, bottom_y;

  /* Get frame-relative bounding box of the text display area of W,
     without mode lines.  Include in this box the left and right
     fringe of W.  */
  window_box (w, ANY_AREA, &x, &y, &width, &height);

  from_y = WINDOW_TO_FRAME_PIXEL_Y (w, run->current_y);
  to_y = WINDOW_TO_FRAME_PIXEL_Y (w, run->desired_y);
  bottom_y = y + height;

  NSLog(@"ios_scroll_run: from_y=%d to_y=%d run_height=%d window_box(x=%d,y=%d,w=%d,h=%d) bottom_y=%d",
        from_y, to_y, run->height, x, y, width, height, bottom_y);

  if (to_y < from_y)
    {
      /* Scrolling up.  Make sure we don't copy part of the mode
         line at the bottom.  */
      if (from_y + run->height > bottom_y)
        height = bottom_y - from_y;
      else
        height = run->height;
      NSLog(@"  scroll UP: copy %d pixels, vacated area at y=%d height=%d", 
            height, to_y + height, from_y - to_y);
    }
  else
    {
      /* Scrolling down.  Make sure we don't copy over the mode line
         at the bottom.  */
      if (to_y + run->height > bottom_y)
        height = bottom_y - to_y;
      else
        height = run->height;
      NSLog(@"  scroll DOWN: copy %d pixels, vacated area at y=%d height=%d",
            height, from_y, to_y - from_y);
    }

  if (height == 0)
    return;

  block_input ();

  gui_clear_cursor (w);

  {
    CGRect srcRect = CGRectMake (x, from_y, width, height);
    CGPoint dest = CGPointMake (x, to_y);
    EmacsView *view = FRAME_IOS_VIEW (f);

    if (view)
      {
        /* Verify coordinate consistency between drawing and copying.  */
        int frame_h = FRAME_PIXEL_HEIGHT (f);
        NSLog(@"  scroll: frame_h=%d (should match offscreen)", frame_h);
        
        [view copyRect:srcRect to:dest];
        
        /* Calculate vacated area.  */
        CGRect vacatedRect;
        if (to_y < from_y)
          {
            /* Scroll UP: vacated area at bottom.  */
            vacatedRect = CGRectMake (x, to_y + height, width, from_y - to_y);
          }
        else
          {
            /* Scroll DOWN: vacated area at top.  */
            vacatedRect = CGRectMake (x, from_y, width, to_y - from_y);
          }
        NSLog(@"  scroll: vacated rect = (%g,%g) %gx%g", 
              vacatedRect.origin.x, vacatedRect.origin.y,
              vacatedRect.size.width, vacatedRect.size.height);
        
        /* Clear the vacated area explicitly.  */
        ios_clear_frame_area (f, (int)vacatedRect.origin.x, (int)vacatedRect.origin.y,
                              (int)vacatedRect.size.width, (int)vacatedRect.size.height);
        
        ios_request_display (view);
      }
  }

  unblock_input ();
}

static void
ios_compute_glyph_string_overhangs (struct glyph_string *s)
{
  IOSTRACE ("ios_compute_glyph_string_overhangs");
}

static void
ios_define_fringe_bitmap (int which, unsigned short *bits, int h, int wd)
{
  IOSTRACE ("ios_define_fringe_bitmap");
}

static void
ios_destroy_fringe_bitmap (int which)
{
  IOSTRACE ("ios_destroy_fringe_bitmap");
}

static void
ios_clear_under_internal_border (struct frame *f)
{
  IOSTRACE ("ios_clear_under_internal_border");

  if (FRAME_LIVE_P (f) && FRAME_INTERNAL_BORDER_WIDTH (f) > 0)
    {
      int border = FRAME_INTERNAL_BORDER_WIDTH (f);
      int width = FRAME_PIXEL_WIDTH (f);
      int height = FRAME_PIXEL_HEIGHT (f);
      int margin = FRAME_TOP_MARGIN_HEIGHT (f);
      int bottom_margin = FRAME_BOTTOM_MARGIN_HEIGHT (f);
      int face_id =
        (FRAME_PARENT_FRAME (f)
         ? (!NILP (Vface_remapping_alist)
            ? lookup_basic_face (NULL, f, CHILD_FRAME_BORDER_FACE_ID)
            : CHILD_FRAME_BORDER_FACE_ID)
         : (!NILP (Vface_remapping_alist)
            ? lookup_basic_face (NULL, f, INTERNAL_BORDER_FACE_ID)
            : INTERNAL_BORDER_FACE_ID));
      struct face *face = FACE_FROM_ID_OR_NULL (f, face_id);

      if (!face)
        face = FRAME_DEFAULT_FACE (f);

      if (!face)
        return;

      CGContextRef context = ios_get_drawing_context (f);
      if (!context)
        return;

      unsigned long bg = face->background;
      CGFloat r = ((bg >> 16) & 0xFF) / 255.0;
      CGFloat g = ((bg >> 8) & 0xFF) / 255.0;
      CGFloat b = (bg & 0xFF) / 255.0;
      CGContextSetRGBFillColor (context, r, g, b, 1.0);

      /* Clear the four border regions.  Convert Y coords.  */
      /* Top border.  */
      CGFloat cg_top = ios_cg_y_for_emacs_y (f, margin, border);
      CGContextFillRect (context, CGRectMake (0, cg_top, width, border));
      
      /* Left border.  */
      CGFloat cg_left_y = ios_cg_y_for_emacs_y (f, 0, height);
      CGContextFillRect (context, CGRectMake (0, cg_left_y, border, height));
      
      /* Right border.  */
      CGContextFillRect (context, CGRectMake (width - border, cg_left_y, border, height));
      
      /* Bottom border.  */
      CGFloat cg_bottom = ios_cg_y_for_emacs_y (f, height - bottom_margin - border, border);
      CGContextFillRect (context, CGRectMake (0, cg_bottom, width, border));
    }
}


/* ==========================================================================

   Display info initialization

   ========================================================================== */

static void
ios_initialize_display_info (struct ios_display_info *dpyinfo)
{
  IOSTRACE ("ios_initialize_display_info");

  /* Get main screen info.  */
  UIScreen *screen = [UIScreen mainScreen];
  CGRect bounds = [screen bounds];
  CGFloat scale = [screen scale];

  dpyinfo->resx = 72.0 * scale;
  dpyinfo->resy = 72.0 * scale;
  dpyinfo->scale_factor = scale;
  dpyinfo->color_p = YES;
  dpyinfo->n_planes = 24;  /* Assume 24-bit color.  */
  dpyinfo->root_window = 42;  /* Placeholder.  */
  dpyinfo->highlight_frame = NULL;
  dpyinfo->ios_focus_frame = NULL;
  dpyinfo->n_fonts = 0;
  dpyinfo->smallest_font_height = 1;
  dpyinfo->smallest_char_width = 1;

  /* Initialize safe area (will be updated when view loads).  */
  dpyinfo->safe_area_top = 0;
  dpyinfo->safe_area_bottom = 0;
  dpyinfo->safe_area_left = 0;
  dpyinfo->safe_area_right = 0;

  dpyinfo->keyboard_visible = false;
  dpyinfo->keyboard_height = 0;

  reset_mouse_highlight (&dpyinfo->mouse_highlight);
}


/* ==========================================================================

   Terminal creation

   ========================================================================== */

static struct terminal *
ios_create_terminal (struct ios_display_info *dpyinfo)
{
  IOSTRACE ("ios_create_terminal");

  struct terminal *terminal;

  terminal = create_terminal (output_ios, &ios_redisplay_interface);

  terminal->display_info.ios = dpyinfo;
  dpyinfo->terminal = terminal;

  /* Set up terminal hooks.  */
  terminal->clear_frame_hook = ios_clear_frame;
  terminal->ring_bell_hook = ios_ring_bell;
  terminal->update_begin_hook = ios_update_begin;
  terminal->update_end_hook = ios_update_end;
  terminal->read_socket_hook = ios_read_socket;
  terminal->frame_up_to_date_hook = ios_frame_up_to_date;
  terminal->defined_color_hook = ios_defined_color;
  terminal->query_frame_background_color = ios_query_frame_background_color;
  terminal->mouse_position_hook = ios_mouse_position;
  terminal->get_focus_frame = ios_get_focus_frame;
  terminal->focus_frame_hook = ios_focus_frame;
  terminal->frame_rehighlight_hook = ios_frame_rehighlight;
  terminal->frame_raise_lower_hook = ios_frame_raise_lower;
  terminal->frame_visible_invisible_hook = ios_make_frame_visible_invisible;
  terminal->fullscreen_hook = ios_fullscreen_hook;
  terminal->iconify_frame_hook = ios_iconify_frame;
  terminal->set_window_size_hook = ios_set_window_size;
  terminal->set_window_size_and_position_hook = ios_set_window_size_and_position;
  terminal->set_frame_offset_hook = ios_set_offset;
  terminal->set_frame_alpha_hook = ios_set_frame_alpha;
  terminal->implicit_set_name_hook = ios_implicitly_set_name;
  terminal->menu_show_hook = NULL;  /* TODO: ios_menu_show */
  terminal->popup_dialog_hook = NULL;  /* TODO: ios_popup_dialog */
  terminal->set_vertical_scroll_bar_hook = ios_set_vertical_scroll_bar;
  terminal->set_horizontal_scroll_bar_hook = ios_set_horizontal_scroll_bar;
  terminal->set_scroll_bar_default_width_hook = ios_set_scroll_bar_default_width;
  terminal->set_scroll_bar_default_height_hook = ios_set_scroll_bar_default_height;
  terminal->condemn_scroll_bars_hook = ios_condemn_scroll_bars;
  terminal->redeem_scroll_bar_hook = ios_redeem_scroll_bar;
  terminal->judge_scroll_bars_hook = ios_judge_scroll_bars;
  terminal->get_string_resource_hook = ios_get_string_resource;
  terminal->free_pixmap = ios_free_pixmap;
  terminal->delete_frame_hook = ios_destroy_window;
  terminal->delete_terminal_hook = ios_delete_terminal;
  terminal->change_tab_bar_height_hook = ios_change_tab_bar_height;
  terminal->set_new_font_hook = ios_new_font;

  return terminal;
}


/* ==========================================================================

   Main terminal initialization

   ========================================================================== */

struct ios_display_info *
ios_term_init (void)
{
  IOSTRACE ("ios_term_init");
  NSLog(@"ios_term_init called");

  struct terminal *terminal;
  struct ios_display_info *dpyinfo;
  static int ios_initialized = 0;

  if (ios_initialized)
    {
      NSLog(@"ios_term_init: already initialized, returning early");
      return ios_display_list;
    }
  ios_initialized = 1;
  NSLog(@"ios_term_init: starting initialization");

  block_input ();

  [outerpool release];
  outerpool = [[NSAutoreleasePool alloc] init];

  baud_rate = 38400;
  Fset_input_interrupt_mode (Qnil);

  /* Set up pipe for interrupt handling.  */
  if (selfds[0] == -1)
    {
      if (emacs_pipe (selfds) != 0)
        {
          fprintf (stderr, "Failed to create pipe: %s\n",
                   emacs_strerror (errno));
          emacs_abort ();
        }

      fcntl (selfds[0], F_SETFL, O_NONBLOCK | fcntl (selfds[0], F_GETFL));
      FD_ZERO (&select_readfds);
      FD_ZERO (&select_writefds);
      pthread_mutex_init (&select_mutex, NULL);
    }

  NSLog(@"ios_term_init: creating pending files array");
  ios_pending_files = [[NSMutableArray alloc] init];

  /* Allocate display info.  */
  NSLog(@"ios_term_init: allocating display info");
  dpyinfo = xzalloc (sizeof *dpyinfo);

  NSLog(@"ios_term_init: calling ios_initialize_display_info");
  ios_initialize_display_info (dpyinfo);
  
  NSLog(@"ios_term_init: calling ios_create_terminal");
  terminal = ios_create_terminal (dpyinfo);

  NSLog(@"ios_term_init: allocating kboard");
  terminal->kboard = allocate_kboard (Qios);
  if (current_kboard == initial_kboard)
    current_kboard = terminal->kboard;
  terminal->kboard->reference_count++;

  /* The display "connection" is now set up, and it must never go away.
     This is the same approach used by Android.  */
  terminal->reference_count = 30000;

  NSLog(@"ios_term_init: setting up display list");
  dpyinfo->next = ios_display_list;
  ios_display_list = dpyinfo;

  /* Load color map from rgb.txt.  Use the static Vios_color_map which
     is protected by staticpro to avoid garbage collection.  */
  NSLog(@"ios_term_init: loading color map from rgb.txt");
  if (NILP (Vios_color_map))
    {
      Lisp_Object color_file = Fexpand_file_name (build_string ("rgb.txt"),
                                                  Vdata_directory);
      Vios_color_map = Fx_load_color_file (color_file);
      if (NILP (Vios_color_map))
        NSLog(@"ios_term_init: WARNING - Could not load rgb.txt from %s", SDATA (color_file));
      else
        NSLog(@"ios_term_init: loaded color map with %ld entries", (long)list_length (Vios_color_map));
    }
  else
    {
      NSLog(@"ios_term_init: using existing color map with %ld entries", (long)list_length (Vios_color_map));
    }
  dpyinfo->color_map = Vios_color_map;

  NSLog(@"ios_term_init: creating name_list_element");
  Lisp_Object ios_display_name = build_string ("ios");
  dpyinfo->name_list_element = Fcons (ios_display_name, Qnil);

  NSLog(@"ios_term_init: setting terminal name");
  terminal->name = xstrdup ("ios");

  NSLog(@"ios_term_init: calling gui_init_fringe (rif=%p)", (void*)terminal->rif);
  if (terminal->rif) {
    NSLog(@"ios_term_init: rif->define_fringe_bitmap=%p", (void*)terminal->rif->define_fringe_bitmap);
  }
  /* NOTE: gui_init_fringe must be called AFTER init_fringe() allocates
     fringe_bitmaps array. Since ios_term_init is called from init_display(),
     which runs BEFORE init_fringe(), we defer the fringe initialization.
     It will be called later from ios_create_frame() when the first frame
     is created, or we can rely on gui_define_fringe_bitmap() to handle
     individual bitmaps on demand. */
  /* gui_init_fringe (terminal->rif); -- deferred, causes SIGSEGV */

  NSLog(@"ios_term_init: calling unblock_input");
  unblock_input ();

  /* Set defaults.  */
  ios_antialias_threshold = 10.0;

  IOSTRACE ("ios_term_init done");
  NSLog(@"ios_term_init completed successfully");

  return dpyinfo;
}


/* ==========================================================================

   Functions required by frame.c and other core modules

   ========================================================================== */

void
frame_set_mouse_pixel_position (struct frame *f, int pix_x, int pix_y)
{
  IOSTRACE ("frame_set_mouse_pixel_position: (%d, %d)", pix_x, pix_y);
  /* On iOS, we cannot programmatically set the touch position.
     This is a no-op.  */
}


char *
get_keysym_name (int keysym)
{
  /* Return NULL for unknown keysyms.  */
  static char buf[16];
  if (keysym >= 0x20 && keysym < 0x7f)
    {
      buf[0] = keysym;
      buf[1] = '\0';
      return buf;
    }
  return NULL;
}


void
set_frame_menubar (struct frame *f, bool deep_p)
{
  IOSTRACE ("set_frame_menubar: deep=%d", deep_p);
  /* On iOS, menus are handled by UIKit.  This is currently a no-op.  */
}


void
ios_term_shutdown (int sig)
{
  IOSTRACE ("ios_term_shutdown");

  /* Cleanup and exit.  */
  [outerpool release];
  outerpool = nil;
}


/* ==========================================================================

   iOS select implementation

   ========================================================================== */

int
ios_select (int nfds, fd_set *readfds, fd_set *writefds,
            fd_set *exceptfds, struct timespec *timeout,
            sigset_t *sigmask)
{
  /* iOS implementation of select with run loop integration.  */
  return pselect (nfds, readfds, writefds, exceptfds, timeout, sigmask);
}

#ifdef HAVE_PTHREAD
void
ios_run_loop_break (void)
{
  /* Interrupt the run loop.  */
  CFRunLoopStop (CFRunLoopGetMain ());
}
#endif


/* ==========================================================================

   Utility functions

   ========================================================================== */

double
ios_frame_scale_factor (struct frame *f)
{
  struct ios_display_info *dpyinfo = FRAME_DISPLAY_INFO (f);
  return dpyinfo ? dpyinfo->scale_factor : 1.0;
}

int
ios_display_pixel_height (struct ios_display_info *dpyinfo)
{
  UIScreen *screen = [UIScreen mainScreen];
  CGRect bounds = [screen nativeBounds];
  return (int)bounds.size.height;
}

int
ios_display_pixel_width (struct ios_display_info *dpyinfo)
{
  UIScreen *screen = [UIScreen mainScreen];
  CGRect bounds = [screen nativeBounds];
  return (int)bounds.size.width;
}

void
ios_release_object (void *obj)
{
  [(id)obj release];
}

void
ios_retain_object (void *obj)
{
  [(id)obj retain];
}

void *
ios_alloc_autorelease_pool (void)
{
  return [[NSAutoreleasePool alloc] init];
}

void
ios_release_autorelease_pool (void *pool)
{
  [(NSAutoreleasePool *)pool release];
}

void
ios_init_pool (void)
{
  if (!outerpool)
    outerpool = [[NSAutoreleasePool alloc] init];
}

void
ios_init_locale (void)
{
  /* Set up locale from iOS settings.  */
  NSLocale *locale = [NSLocale currentLocale];
  NSString *langCode = [locale languageCode];
  if (langCode)
    setenv ("LANG", [[langCode stringByAppendingString:@".UTF-8"] UTF8String], 0);
}


/* ==========================================================================

   GC marking

   ========================================================================== */

void
mark_iosterm (void)
{
  /* Mark Lisp objects used by the iOS terminal.  */
  struct ios_display_info *dpyinfo;

  for (dpyinfo = ios_display_list; dpyinfo; dpyinfo = dpyinfo->next)
    {
      mark_object (dpyinfo->name_list_element);
      mark_object (dpyinfo->rdb);
    }
}


/* ==========================================================================

   Frame parameter handlers

   ========================================================================== */

frame_parm_handler ios_frame_parm_handlers[] =
{
  gui_set_autoraise,
  gui_set_autolower,
  ios_set_background_color,
  ios_set_border_color,
  gui_set_border_width,
  ios_set_cursor_color,
  ios_set_cursor_type,
  gui_set_font,
  ios_set_foreground_color,
  ios_set_icon_name,
  ios_set_icon_type,
  ios_set_child_frame_border_width,
  ios_set_internal_border_width,
  gui_set_right_divider_width,
  gui_set_bottom_divider_width,
  NULL, /* ios_set_menu_bar_lines (no menu bar on iOS) */
  ios_set_mouse_color,
  ios_explicitly_set_name,
  gui_set_scroll_bar_width,
  gui_set_scroll_bar_height,
  NULL, /* ios_set_title */
  gui_set_unsplittable,
  gui_set_vertical_scroll_bars,
  gui_set_horizontal_scroll_bars,
  gui_set_visibility,
  ios_set_tab_bar_lines,
  ios_set_tool_bar_lines,
  NULL, /* ios_set_scroll_bar_foreground */
  NULL, /* ios_set_scroll_bar_background */
  gui_set_screen_gamma,
  gui_set_line_spacing,
  gui_set_left_fringe,
  gui_set_right_fringe,
  NULL, /* ios_set_wait_for_wm */
  gui_set_fullscreen,
  gui_set_font_backend,
  gui_set_alpha,
  NULL, /* ios_set_sticky */
  NULL, /* ios_set_tool_bar_position */
  NULL, /* ios_set_inhibit_double_buffering */
  NULL, /* ios_set_undecorated */
  NULL, /* ios_set_parent_frame */
  NULL, /* ios_set_skip_taskbar */
  NULL, /* ios_set_no_focus_on_map */
  NULL, /* ios_set_no_accept_focus */
  NULL, /* ios_set_z_group */
  NULL, /* ios_set_override_redirect */
  gui_set_no_special_glyphs,
  gui_set_alpha_background,
  NULL, /* ios_set_borders_respect_alpha_background */
  NULL, /* ios_set_use_frame_synchronization */
  /* iOS-specific frame parameters (matching NS patches).  */
  ios_set_background_blur,
  ios_set_alpha_elements,
  ios_set_fontsize,
};


/* ==========================================================================

   Symbol initialization

   ========================================================================== */

void
syms_of_iosterm (void)
{
  IOSTRACE ("syms_of_iosterm");

  /* Protect color_map from garbage collection.  */
  Vios_color_map = Qnil;
  staticpro (&Vios_color_map);

  ios_antialias_threshold = 10.0;
  PDUMPER_REMEMBER_SCALAR (ios_antialias_threshold);

  /* Modifier key symbols.  */
  DEFSYM (Qmodifier_value, "modifier-value");
  DEFSYM (Qalt, "alt");
  DEFSYM (Qhyper, "hyper");
  DEFSYM (Qmeta, "meta");
  DEFSYM (Qsuper, "super");
  DEFSYM (Qcontrol, "control");
  DEFSYM (QUTF8_STRING, "UTF8_STRING");

  DEFSYM (Qfile, "file");
  DEFSYM (Qurl, "url");

  /* iOS-specific symbols.  */
  DEFSYM (Qios, "ios");
  DEFSYM (Qdark, "dark");
  DEFSYM (Qlight, "light");
  DEFSYM (Qrun_hook_with_args, "run-hook-with-args");
  DEFSYM (Qios_system_appearance_change_functions, "ios-system-appearance-change-functions");
  DEFSYM (Qios_background_blur, "ios-background-blur");

  Fput (Qalt, Qmodifier_value, make_fixnum (alt_modifier));
  Fput (Qhyper, Qmodifier_value, make_fixnum (hyper_modifier));
  Fput (Qmeta, Qmodifier_value, make_fixnum (meta_modifier));
  Fput (Qsuper, Qmodifier_value, make_fixnum (super_modifier));
  Fput (Qcontrol, Qmodifier_value, make_fixnum (ctrl_modifier));

  DEFVAR_LISP ("ios-input-font", Vios_input_font,
    doc: /* The font specified in the last iOS event.  */);
  Vios_input_font = Qnil;

  DEFVAR_LISP ("ios-input-fontsize", Vios_input_fontsize,
    doc: /* The fontsize specified in the last iOS event.  */);
  Vios_input_fontsize = Qnil;

  DEFVAR_LISP ("ios-input-file", Vios_input_file,
    doc: /* The file specified in the last iOS event.  */);
  Vios_input_file = Qnil;

  DEFVAR_LISP ("ios-working-text", Vios_working_text,
    doc: /* String for visualizing working composition sequence.  */);
  Vios_working_text = Qnil;

  DEFVAR_LISP ("ios-alternate-modifier", Vios_alternate_modifier,
    doc: /* Behavior of the Option/Alt key.
Value is `control', `meta', `alt', `super', `hyper' or `none'.
If `none', the key is ignored by Emacs.  */);
  Vios_alternate_modifier = Qmeta;

  DEFVAR_LISP ("ios-command-modifier", Vios_command_modifier,
    doc: /* Behavior of the Command key.
Value is `control', `meta', `alt', `super', `hyper' or `none'.
If `none', the key is ignored by Emacs.  */);
  Vios_command_modifier = Qsuper;

  DEFVAR_LISP ("ios-control-modifier", Vios_control_modifier,
    doc: /* Behavior of the Control key.
Value is `control', `meta', `alt', `super', `hyper' or `none'.  */);
  Vios_control_modifier = Qcontrol;

  DEFVAR_BOOL ("ios-use-native-fullscreen", ios_use_native_fullscreen,
    doc: /* Whether to use iOS native fullscreen.
On iOS, apps are typically always fullscreen or in split view.  */);
  ios_use_native_fullscreen = YES;

  DEFVAR_BOOL ("ios-antialias-text", ios_antialias_text,
    doc: /* Whether to antialias text.  */);
  ios_antialias_text = YES;

  /* System appearance (dark/light mode).  */
  DEFVAR_LISP ("ios-system-appearance", Vios_system_appearance,
    doc: /* Current system appearance, i.e. `dark' or `light'.
This reflects the current iOS interface style.  */);
  Vios_system_appearance = Qnil;

  DEFVAR_LISP ("ios-system-appearance-change-functions",
               Vios_system_appearance_change_functions,
    doc: /* Functions to call when the system appearance changes.
Each function is called with a single argument, which corresponds to the new
system appearance (`dark' or `light').

This hook is also run once at startup.

Example usage:
    (defun my/load-theme (appearance)
      \"Load theme based on system APPEARANCE.\"
      (mapc #'disable-theme custom-enabled-themes)
      (pcase appearance
        (\='light (load-theme \='modus-operandi t))
        (\='dark (load-theme \='modus-vivendi t))))

    (add-hook \='ios-system-appearance-change-functions #\='my/load-theme)  */);
  Vios_system_appearance_change_functions = Qnil;

  /* Background blur effect.  */
  DEFVAR_LISP ("ios-background-blur", Vios_background_blur,
    doc: /* Background blur radius for translucent frames.
A positive number enables background blur with that radius.
Only effective when `alpha-background' is less than 1.0.
Set to 0 or nil to disable.  */);
  Vios_background_blur = Qnil;

  /* Per-element alpha transparency control.  */
  DEFVAR_LISP ("ios-alpha-elements", Vios_alpha_elements,
    doc: /* Control which frame elements respect alpha-background transparency.
Value can be:
  - nil or `ios-alpha-all': All elements are transparent (default)
  - A list of symbols controlling individual elements:
    `ios-alpha-default': Default face background
    `ios-alpha-fringe': Fringe area
    `ios-alpha-box': Box around text
    `ios-alpha-stipple': Stipple patterns
    `ios-alpha-relief': Relief shadows
    `ios-alpha-glyphs': Glyph backgrounds

Only listed elements will have transparency applied.  */);
  Vios_alpha_elements = Qnil;

  /* Alpha element symbols.  */
  DEFSYM (Qios_alpha_elements, "ios-alpha-elements");
  DEFSYM (Qios_alpha_all, "ios-alpha-all");
  DEFSYM (Qios_alpha_default, "ios-alpha-default");
  DEFSYM (Qios_alpha_fringe, "ios-alpha-fringe");
  DEFSYM (Qios_alpha_box, "ios-alpha-box");
  DEFSYM (Qios_alpha_stipple, "ios-alpha-stipple");
  DEFSYM (Qios_alpha_relief, "ios-alpha-relief");
  DEFSYM (Qios_alpha_glyphs, "ios-alpha-glyphs");

  /* Variables expected by cus-start.el for GUI systems.  */
  ios_debug_log ("DEFVAR_BOOL x-use-underline-position-properties about to be defined");
  DEFVAR_BOOL ("x-use-underline-position-properties",
	       x_use_underline_position_properties,
     doc: /* Non-nil means make use of UNDERLINE_POSITION font properties.
A value of nil means ignore them.  If you encounter fonts with bogus
UNDERLINE_POSITION font properties, set this to nil.
NOTE: Not all window systems currently support this.  */);
  x_use_underline_position_properties = true;
  DEFSYM (Qx_use_underline_position_properties,
	  "x-use-underline-position-properties");
  ios_debug_log ("DEFVAR_BOOL x-use-underline-position-properties DEFINED");

  DEFVAR_BOOL ("x-underline-at-descent-line",
	       x_underline_at_descent_line,
     doc: /* Non-nil means to draw the underline at the descent line.
A value of nil means to draw the underline according to the value of the
variable `underline-minimum-offset' or if the text underlined has no
UNDERLINE_POSITION font property, at the baseline level.  */);
  x_underline_at_descent_line = false;

  /* Test: Call terminal-list to see if it works early in init */
  NSLog(@"syms_of_iosterm: about to call Fterminal_list for testing");
  Lisp_Object tlist = Fterminal_list ();
  NSLog(@"syms_of_iosterm: Fterminal_list returned (length=%ld)", (long)XFIXNUM (Flength (tlist)));

  /* Provide the iOS feature so Lisp code can detect we're running on iOS.  */
  Fprovide (Qios, Qnil);
  ios_debug_log ("Fprovide (Qios, Qnil) called - (featurep 'ios) should now return t");
}

#endif /* HAVE_IOS */
