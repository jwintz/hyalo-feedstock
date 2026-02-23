/* -*- objc -*- */
/* Definitions and headers for communication with iOS/UIKit API.
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

#ifndef EMACS_IOSTERM_H
#define EMACS_IOSTERM_H

/* Flag set by the iOS app to indicate GUI is available.
   This is checked in init_display_interactive() to decide whether
   to initialize the iOS window system.  */
extern bool ios_init_gui;

/* Bootstrap progress reporting - called from lread.c during file loading.  */
extern void ios_notify_bootstrap_start (void);
extern void ios_report_load_progress (const char *filename);
extern void ios_report_bootstrap_complete (void);

/* Signal that events are available - called from main thread when UIKit events arrive.  */
extern void ios_signal_event_available (void);

#include "dispextern.h"
#include "frame.h"
#include "character.h"
#include "font.h"
#include "sysselect.h"
#include "sysstdio.h"

#ifdef HAVE_IOS
#ifdef __OBJC__

/* CGFloat compatibility.  On iOS, CGFloat is always defined.  */
typedef CGFloat EmacsCGFloat;

/* Get the drawing context for a frame.  Used by macfont.m for text rendering.
   Returns the offscreen buffer context if available, otherwise UIGraphicsGetCurrentContext.  */
extern CGContextRef ios_frame_get_drawing_context (struct frame *f);

/* ==========================================================================

   Trace support

   ========================================================================== */

/* Uncomment the following line to enable trace.  */

/* #define IOSTRACE_ENABLED 1 */

#ifndef IOSTRACE_ENABLED
#define IOSTRACE_ENABLED 0
#endif

#if IOSTRACE_ENABLED

extern volatile int iostrace_num;
extern volatile int iostrace_depth;
extern volatile int iostrace_enabled_global;

void iostrace_leave(int *);
void iostrace_restore_global_trace_state(int *);

#define IOSTRACE_MSG_NO_DASHES(...)                                         \
  do                                                                        \
    {                                                                       \
      if (iostrace_enabled_global)                                          \
        {                                                                   \
          fprintf (stderr, "%-10s:%5d: [%5d]%.*s",                          \
                   __FILE__, __LINE__, iostrace_num++,                      \
                   2*iostrace_depth, "  | | | | | | | | | | | | | | | .."); \
          fprintf (stderr, __VA_ARGS__);                                    \
          putc ('\n', stderr);                                              \
        }                                                                   \
    }                                                                       \
  while(0)

#define IOSTRACE_MSG(...) IOSTRACE_MSG_NO_DASHES("+--- " __VA_ARGS__)

#define IOSTRACE_WHEN(cond, ...)                                            \
  __attribute__ ((cleanup (iostrace_restore_global_trace_state)))           \
  int iostrace_saved_enabled_global = iostrace_enabled_global;              \
  __attribute__ ((cleanup (iostrace_leave)))                                \
  int iostrace_enabled = iostrace_enabled_global && (cond);                 \
  if (iostrace_enabled) { ++iostrace_depth; }                               \
  else { iostrace_enabled_global = 0; }                                     \
  IOSTRACE_MSG_NO_DASHES(__VA_ARGS__);

#define IOSTRACE_UNSILENCE() do { iostrace_enabled_global = 1; } while(0)

#endif /* IOSTRACE_ENABLED */

#define IOSTRACE(...)              IOSTRACE_WHEN(1, __VA_ARGS__)
#define IOSTRACE_UNLESS(cond, ...) IOSTRACE_WHEN(!(cond), __VA_ARGS__)

/* Non-trace replacement versions.  */
#ifndef IOSTRACE_WHEN
#define IOSTRACE_WHEN(...)
#endif

#ifndef IOSTRACE_MSG
#define IOSTRACE_MSG(...)
#endif

#ifndef IOSTRACE_UNSILENCE
#define IOSTRACE_UNSILENCE()
#endif


/* If the compiler doesn't support instancetype, map it to id.  */
#ifndef NATIVE_OBJC_INSTANCETYPE
typedef id instancetype;
#endif


/* ==========================================================================

   UIColor, EmacsColor category.

   ========================================================================== */

@interface UIColor (EmacsColor)
+ (UIColor *)colorForEmacsRed:(CGFloat)red green:(CGFloat)green
                         blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (UIColor *)colorWithUnsignedLong:(unsigned long)c;
- (unsigned long)unsignedLong;
@end


@interface NSString (EmacsString)
+ (NSString *)stringWithLispString:(Lisp_Object)string;
- (Lisp_Object)lispString;
@end


/* ==========================================================================

   The Emacs iOS Application Delegate

   ========================================================================== */

@interface EmacsAppDelegate : UIResponder <UIApplicationDelegate>
{
@public
  int nextappdefined;
}

@property (strong, nonatomic) UIWindow *window;

- (void)applicationDidFinishLaunching:(UIApplication *)application;
- (void)applicationWillResignActive:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationWillEnterForeground:(UIApplication *)application;
- (void)applicationDidBecomeActive:(UIApplication *)application;
- (void)applicationWillTerminate:(UIApplication *)application;
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options;
- (void)fd_handler:(id)unused;
- (void)timeout_handler:(NSTimer *)timedEntry;

@end


/* ==========================================================================

   The Emacs iOS Scene Delegate (iOS 13+)

   ========================================================================== */

API_AVAILABLE(ios(13.0))
@interface EmacsSceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions;
- (void)sceneDidDisconnect:(UIScene *)scene;
- (void)sceneDidBecomeActive:(UIScene *)scene;
- (void)sceneWillResignActive:(UIScene *)scene;
- (void)sceneWillEnterForeground:(UIScene *)scene;
- (void)sceneDidEnterBackground:(UIScene *)scene;

@end


/* ==========================================================================

   The main Emacs view

   ========================================================================== */

@interface EmacsView : UIView <UIKeyInput, UITextInputTraits>
{
  BOOL windowClosing;
  NSString *workingText;
  BOOL processingCompose;
  int fs_state;

@public
  struct frame *emacsframe;
  int scrollbarsNeedingUpdate;
  CGRect ios_userRect;
  
  /* Offscreen bitmap for Emacs drawing.  */
  CGContextRef offscreenContext;
  void *offscreenData;
  size_t offscreenWidth;      /* Backing pixels (logical × scale) */
  size_t offscreenHeight;     /* Backing pixels (logical × scale) */
  CGFloat backingScaleFactor; /* Screen scale (e.g., 2.0 for Retina) */
  BOOL offscreenHasContent;
  BOOL needsBackgroundClear;  /* Set when background color changes */
  
  /* Pending resize - set by main thread, processed by Emacs thread.
     This avoids race conditions where context is freed while drawing.  */
  size_t pendingResizeWidth;  /* Logical pixels, 0 = no pending resize */
  size_t pendingResizeHeight;
  
  /* Keyboard height for layout.  Safe area is now handled by Auto Layout.  */
  CGFloat keyboardHeight;
  
  /* Modifier keys for virtual keyboard (sticky modifiers).  */
  BOOL modCtrl;
  BOOL modMeta;
  
  /* Key repeat timer for accessory bar buttons.  */
  NSTimer *keyRepeatTimer;
  SEL keyRepeatAction;
  
  /* Hardware keyboard repeat.  */
  NSTimer *hwKeyRepeatTimer;
  struct input_event hwKeyRepeatEvent;
  BOOL hwKeyRepeatActive;
}

/* UIView overrides.  */
- (void)drawRect:(CGRect)rect;
- (void)layoutSubviews;

/* Touch handling.  */
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;

/* UIKeyInput protocol.  */
- (BOOL)hasText;
- (void)insertText:(NSString *)text;
- (void)deleteBackward;
- (BOOL)canBecomeFirstResponder;
- (BOOL)canResignFirstResponder;

/* Emacs-side interface.  */
- (instancetype)initFrameFromEmacs:(struct frame *)f;
- (instancetype)initFrameFromEmacsOnMainThread:(struct frame *)f;
- (void)setWindowClosing:(BOOL)closing;
- (void)deleteWorkingText;
- (void)handleFS;
- (void)setFSValue:(int)value;
- (int)fullscreenState;
- (void)toggleFullScreen:(id)sender;
- (BOOL)isFullscreen;
- (void)markOffscreenHasContent;
- (void)clearOffscreenWithBackgroundColor;

/* Keyboard handling.  */
- (void)pressesBegan:(NSSet<UIPress *> *)presses
           withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0));
- (void)pressesEnded:(NSSet<UIPress *> *)presses
           withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0));
- (void)pressesChanged:(NSSet<UIPress *> *)presses
             withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0));
- (void)pressesCancelled:(NSSet<UIPress *> *)presses
               withEvent:(UIPressesEvent *)event API_AVAILABLE(ios(9.0));

/* Frame management.  */
- (void)windowDidBecomeKey;
- (void)windowDidResignKey;
- (void)setFrame:(CGRect)frame;

/* Safe area handling.  */
- (UIEdgeInsets)safeAreaInsets;
- (void)safeAreaInsetsDidChange;

/* Drawing.  */
- (void)copyRect:(CGRect)srcRect to:(CGPoint)dest;
- (CGContextRef)getOffscreenContext;
- (void)ensureOffscreenContext;
- (void)ensureOffscreenContextForWidth:(size_t)width height:(size_t)height;
- (void)setEmacsFrame:(struct frame *)f;
- (struct frame *)emacsFrame;
- (BOOL)offscreenHasContent;

+ (EmacsView *)createFrameView:(struct frame *)f;

@end


/* ==========================================================================

   Emacs View Controller

   ========================================================================== */

@interface EmacsViewController : UIViewController

@property (nonatomic, strong) EmacsView *emacsView;

- (instancetype)initWithFrame:(struct frame *)f;
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)viewWillDisappear:(BOOL)animated;
- (void)viewDidDisappear:(BOOL)animated;
- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection;
- (UIStatusBarStyle)preferredStatusBarStyle;
- (BOOL)prefersStatusBarHidden;
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures;
- (BOOL)prefersHomeIndicatorAutoHidden;

@end


/* ==========================================================================

   Context menus (iOS 13+)

   ========================================================================== */

API_AVAILABLE(ios(13.0))
@interface EmacsContextMenuInteraction : NSObject <UIContextMenuInteractionDelegate>
{
  struct frame *frame;
}

- (instancetype)initWithFrame:(struct frame *)f;
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location;
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
       willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
                                               animator:(id<UIContextMenuInteractionCommitAnimating>)animator;

@end


/* ==========================================================================

   Tooltip view

   ========================================================================== */

@interface EmacsTooltip : NSObject
{
  UIView *tooltipView;
  UILabel *textLabel;
  NSTimer *timer;
}

- (instancetype)init;
- (void)setText:(char *)text;
- (void)setBackgroundColor:(UIColor *)col;
- (void)setForegroundColor:(UIColor *)col;
- (void)showAtX:(int)x Y:(int)y for:(int)seconds;
- (void)hide;
- (BOOL)isActive;
- (CGRect)frame;
- (void)moveTo:(CGPoint)point;

@end


/* ==========================================================================

   Images and stippling

   ========================================================================== */

@interface EmacsImage : UIImage
{
  CGImageRef cgImage;
  unsigned char *pixmapData[5];
  CGImageRef stippleMask;

@public
  CGAffineTransform transform;
  BOOL smoothing;
}

+ (instancetype)allocInitFromFile:(Lisp_Object)file;
- (void)dealloc;
- (instancetype)initFromXBM:(unsigned char *)bits width:(int)w height:(int)h
                         fg:(unsigned long)fg bg:(unsigned long)bg
               reverseBytes:(BOOL)reverse;
- (instancetype)initForXPMWithDepth:(int)depth width:(int)width height:(int)height;
- (void)setPixmapData;
- (unsigned long)getPixelAtX:(int)x Y:(int)y;
- (void)setPixelAtX:(int)x Y:(int)y toRed:(unsigned char)r
              green:(unsigned char)g blue:(unsigned char)b
              alpha:(unsigned char)a;
- (void)setAlphaAtX:(int)x Y:(int)y to:(unsigned char)a;
- (CGImageRef)stippleMask;
- (Lisp_Object)getMetadata;
- (BOOL)setFrame:(unsigned int)index;
- (void)setTransform:(double[3][3])m;
- (void)setSmoothing:(BOOL)s;
- (size_t)sizeInBytes;

@end


/* ==========================================================================

   Scrollbars

   ========================================================================== */

@interface EmacsScroller : UIScrollView <UIScrollViewDelegate>
{
  struct window *window;
  struct frame *frame;

  float min_portion;
  int pixel_length;
  enum scroll_bar_part last_hit_part;

  BOOL condemned;
  BOOL horizontal;

  /* Optimize against excessive positioning calls generated by Emacs.  */
  int em_position;
  int em_portion;
  int em_whole;
}

- (void)mark;
- (instancetype)initFrame:(CGRect)r window:(Lisp_Object)win;
- (void)setFrame:(CGRect)r;
- (instancetype)setPosition:(int)position portion:(int)portion whole:(int)whole;
- (int)checkSamePosition:(int)position portion:(int)portion whole:(int)whole;
- (void)sendScrollEventAtLoc:(float)loc fromEvent:(UIEvent *)e;
- (instancetype)condemn;
- (instancetype)reprieve;
- (bool)judge;
+ (CGFloat)scrollerWidth;
+ (CGFloat)scrollerHeight;

/* UIScrollViewDelegate.  */
- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;

@end


/* ==========================================================================

   Layer for double-buffered rendering

   ========================================================================== */

@interface EmacsLayer : CALayer
{
  NSMutableArray *cache;
  CGColorSpaceRef colorSpace;
  /* IOSurfaceRef not available on iOS Simulator - use CGImage backing.  */
  CGContextRef context;
  bool doubleBuffered;
}

- (id)initWithDoubleBuffered:(bool)db;
- (void)setColorSpace:(CGColorSpaceRef)cs;
- (void)setDoubleBuffered:(bool)db;
- (CGContextRef)getContext;

@end


#endif  /* __OBJC__ */


/* ==========================================================================

   Non-OO data structures

   ========================================================================== */

/* Special keycodes that we pass down the event chain.  */
#define KEY_IOS_POWER_OFF               ((1<<28)|(0<<16)|1)
#define KEY_IOS_OPEN_FILE               ((1<<28)|(0<<16)|2)
#define KEY_IOS_CHANGE_FONT             ((1<<28)|(0<<16)|7)
#define KEY_IOS_PUT_WORKING_TEXT        ((1<<28)|(0<<16)|9)
#define KEY_IOS_UNPUT_WORKING_TEXT      ((1<<28)|(0<<16)|10)
#define KEY_IOS_TOGGLE_TOOLBAR          ((1<<28)|(0<<16)|13)
#define KEY_IOS_APP_FOREGROUND          ((1<<28)|(0<<16)|15)
#define KEY_IOS_APP_BACKGROUND          ((1<<28)|(0<<16)|16)
#define KEY_IOS_KEYBOARD_SHOW           ((1<<28)|(0<<16)|17)
#define KEY_IOS_KEYBOARD_HIDE           ((1<<28)|(0<<16)|18)
#define KEY_IOS_SAFE_AREA_CHANGE        ((1<<28)|(0<<16)|19)

/* Bitmap record structure.  */
struct ios_bitmap_record
{
#ifdef __OBJC__
  EmacsImage *img;
#else
  void *img;
#endif
  char *file;
  int refcount;
  int height, width, depth;
};

/* Touch point tracking structure.  */
struct ios_touch_point
{
  /* The next touch in the list.  */
  struct ios_touch_point *next;

  /* Unique touch identifier.  */
  unsigned long touch_id;

  /* Last known position.  */
  int x, y;

  /* Whether this touch is on the tool bar.  */
  bool tool_bar_p;
};

/* Initialized in ios_initialize_display_info().  */
struct ios_display_info
{
  /* Chain of all ios_display_info structures.  */
  struct ios_display_info *next;

  /* The generic display parameters corresponding to this iOS display.  */
  struct terminal *terminal;

  /* This is a cons cell of the form (NAME . FONT-LIST-CACHE).  */
  Lisp_Object name_list_element;

  /* The number of fonts loaded.  */
  int n_fonts;

  /* Minimum width over all characters in all fonts in font_table.  */
  int smallest_char_width;

  /* Minimum font height over all fonts in font_table.  */
  int smallest_font_height;

  struct ios_bitmap_record *bitmaps;
  ptrdiff_t bitmaps_size;
  ptrdiff_t bitmaps_last;

  /* DPI resolution of this screen.  */
  double resx, resy;

  /* Scale factor for Retina displays.  */
  double scale_factor;

  /* Mask of things that cause the touch to be grabbed.  */
  int grabbed;

  int n_planes;

  int color_p;

  Window root_window;

  /* Xism for compatibility.  */
  Lisp_Object rdb;

  /* The cursor to use for vertical scroll bars (unused on iOS but kept
     for compatibility).  */
  Emacs_Cursor vertical_scroll_bar_cursor;

  /* The cursor to use for horizontal scroll bars.  */
  Emacs_Cursor horizontal_scroll_bar_cursor;

  /* Information about the range of text currently shown in
     mouse-face.  */
  Mouse_HLInfo mouse_highlight;

  struct frame *highlight_frame;
  struct frame *ios_focus_frame;

  /* Color map loaded from rgb.txt.  A list of (NAME . COLOR-VALUE) pairs.  */
  Lisp_Object color_map;

  /* The frame where the touch was last time we reported a touch event.  */
  struct frame *last_mouse_frame;

  /* The frame where the touch was last time we reported a touch motion.  */
  struct frame *last_mouse_motion_frame;

  /* Position where the touch was last time we reported a motion.
     This is a position on last_mouse_motion_frame.  */
  int last_mouse_motion_x;
  int last_mouse_motion_y;

  /* Where the touch was last time we reported a touch position.  */
  CGRect last_mouse_glyph;

  /* Time of last touch movement.  */
  Time last_mouse_movement_time;

  /* The scroll bar in which the last motion event occurred.  */
#ifdef __OBJC__
  EmacsScroller *last_mouse_scroll_bar;
#else
  void *last_mouse_scroll_bar;
#endif

  /* Safe area insets for the current scene.  */
  double safe_area_top;
  double safe_area_bottom;
  double safe_area_left;
  double safe_area_right;

  /* Keyboard visibility and frame.  */
  bool keyboard_visible;
  double keyboard_height;
};

/* This is a chain of structures for all the iOS displays currently in use.
   On iOS there is typically only one display.  */
extern struct ios_display_info *ios_display_list;

/* For compatibility with code that uses x_display_list.  */
#define x_display_list ios_display_list

extern long context_menu_value;


/* Per-frame output data.  */
struct ios_output
{
#ifdef __OBJC__
  EmacsView *view;
  id miniimage;
  UIColor *cursor_color;
  UIColor *foreground_color;
  UIColor *background_color;
  UIColor *relief_background_color;
  UIColor *light_relief_color;
  UIColor *dark_relief_color;
  EmacsViewController *viewController;
#else
  void *view;
  void *miniimage;
  void *cursor_color;
  void *foreground_color;
  void *background_color;
  void *relief_background_color;
  void *light_relief_color;
  void *dark_relief_color;
  void *viewController;
#endif

  /* Track the last known default face background for detecting theme changes.  */
  unsigned long last_face_background;
  
  /* Cursors - iOS doesn't have mouse cursors, but we keep these for
     API compatibility and potential future use with stylus/pencil.  */
  Emacs_Cursor text_cursor;
  Emacs_Cursor nontext_cursor;
  Emacs_Cursor modeline_cursor;
  Emacs_Cursor hand_cursor;
  Emacs_Cursor hourglass_cursor;
  Emacs_Cursor horizontal_drag_cursor;
  Emacs_Cursor vertical_drag_cursor;
  Emacs_Cursor left_edge_cursor;
  Emacs_Cursor top_left_corner_cursor;
  Emacs_Cursor top_edge_cursor;
  Emacs_Cursor top_right_corner_cursor;
  Emacs_Cursor right_edge_cursor;
  Emacs_Cursor bottom_right_corner_cursor;
  Emacs_Cursor bottom_edge_cursor;
  Emacs_Cursor bottom_left_corner_cursor;

  /* iOS-specific.  */
  Emacs_Cursor current_pointer;

  /* Window descriptors.  */
  Window window_desc, parent_desc;
  char explicit_parent;

  struct font *font;
  int baseline_offset;

  /* If a fontset is specified for this frame instead of font, this
     value contains an ID of the fontset, else -1.  */
  int fontset;

  int icon_top;
  int icon_left;

  /* The size of the extra width currently allotted for vertical
     scroll bars, in pixels.  */
  int vertical_scroll_bar_extra;

  /* The height of the status bar (if visible).  */
  int statusbar_height;

  /* This is the Emacs structure for the iOS display this frame is on.  */
  struct ios_display_info *display_info;

  /* Non-zero if we are zooming (maximizing) the frame.  */
  int zooming;

  /* Non-zero if we are doing an animation.  */
  int in_animation;

  /* Is the frame double buffered?  */
  bool double_buffered;

  /* Background blur radius (from ios-background-blur frame parameter).  */
  int background_blur;

  /* Per-element transparency control (from ios-alpha-elements frame parameter).  */
  Lisp_Object alpha_elements;

  /* Active touch points on this frame.  */
  struct ios_touch_point *touch_points;

  /* Safe area insets for this specific frame.  */
  double safe_area_top;
  double safe_area_bottom;
  double safe_area_left;
  double safe_area_right;

  /* Font size for this frame.  */
  int fontsize;
};

/* This dummy declaration needed to support TTYs.  */
struct x_output
{
  int unused;
};


/* ==========================================================================

   Frame access macros

   ========================================================================== */

/* This gives the ios_display_info structure for the display F is on.  */
#define FRAME_DISPLAY_INFO(f) ((f)->output_data.ios->display_info)
#define FRAME_OUTPUT_DATA(f) ((f)->output_data.ios)
#define FRAME_IOS_WINDOW(f) ((f)->output_data.ios->window_desc)
#define FRAME_NATIVE_WINDOW(f) FRAME_IOS_WINDOW (f)

#define FRAME_FOREGROUND_COLOR(f) ((f)->output_data.ios->foreground_color)
#define FRAME_BACKGROUND_COLOR(f) ((f)->output_data.ios->background_color)

#define IOS_FACE_FOREGROUND(f) ((f)->foreground)
#define IOS_FACE_BACKGROUND(f) ((f)->background)

#define FRAME_DEFAULT_FACE(f) FACE_FROM_ID_OR_NULL (f, DEFAULT_FACE_ID)

#define FRAME_IOS_VIEW(f) ((f)->output_data.ios->view)
#define FRAME_CURSOR_COLOR(f) ((f)->output_data.ios->cursor_color)
#define FRAME_POINTER_TYPE(f) ((f)->output_data.ios->current_pointer)

#define FRAME_FONT(f) ((f)->output_data.ios->font)

#define FRAME_DOUBLE_BUFFERED(f) ((f)->output_data.ios->double_buffered)

/* Background blur frame parameter (iOS equivalent of ns-background-blur).  */
#define FRAME_IOS_BACKGROUND_BLUR(f) ((f)->output_data.ios->background_blur)

/* Per-element alpha control (iOS equivalent of ns-alpha-elements).  */
#define FRAME_IOS_ALPHA_ELEMENTS(f) ((f)->output_data.ios->alpha_elements)

#ifdef __OBJC__
#define XIOS_SCROLL_BAR(vec) ((id) xmint_pointer (vec))
#else
#define XIOS_SCROLL_BAR(vec) xmint_pointer (vec)
#endif

/* Compute pixel height of the status bar.  */
#define FRAME_IOS_STATUSBAR_HEIGHT(f) \
  ((f)->output_data.ios->statusbar_height)

/* Scroll bar adjustments.  */
#define IOS_SCROLL_BAR_ADJUST(w, f)				\
  (WINDOW_HAS_VERTICAL_SCROLL_BAR_ON_LEFT (w) ?			\
   (FRAME_SCROLL_BAR_COLS (f) * FRAME_COLUMN_WIDTH (f)		\
    - IOS_SCROLL_BAR_WIDTH (f)) : 0)

#define IOS_SCROLL_BAR_ADJUST_HORIZONTALLY(w, f)	\
  (WINDOW_HAS_HORIZONTAL_SCROLL_BARS (w) ?		\
   (FRAME_SCROLL_BAR_LINES (f) * FRAME_LINE_HEIGHT (f)	\
    - IOS_SCROLL_BAR_HEIGHT (f)) : 0)

#define FRAME_IOS_FONT_TABLE(f) (FRAME_DISPLAY_INFO (f)->font_table)

#define FRAME_FONTSET(f) ((f)->output_data.ios->fontset)

#define FRAME_BASELINE_OFFSET(f) ((f)->output_data.ios->baseline_offset)
#define BLACK_PIX_DEFAULT(f) 0x000000
#define WHITE_PIX_DEFAULT(f) 0xFFFFFF

/* First position where characters can be shown (instead of scrollbar, if
   it is on left).  */
#define FIRST_CHAR_POSITION(f)				\
  (! (FRAME_HAS_VERTICAL_SCROLL_BARS_ON_LEFT (f)) ? 0	\
   : FRAME_SCROLL_BAR_COLS (f))


/* ==========================================================================

   Function declarations

   ========================================================================== */

extern void ios_set_background_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_border_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_cursor_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_cursor_type (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_foreground_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_icon_name (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_icon_type (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_child_frame_border_width (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_internal_border_width (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_mouse_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_explicitly_set_name (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_tab_bar_lines (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_tool_bar_lines (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_fontsize (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_background_blur (struct frame *f, Lisp_Object arg, Lisp_Object oldval);
extern void ios_set_alpha_elements (struct frame *f, Lisp_Object arg, Lisp_Object oldval);

extern Lisp_Object Fx_hide_tip (void);
extern Lisp_Object Fxw_display_color_p (Lisp_Object terminal);
extern Lisp_Object Fx_display_grayscale_p (Lisp_Object terminal);
extern Lisp_Object Fx_display_pixel_width (Lisp_Object terminal);
extern Lisp_Object Fx_display_pixel_height (Lisp_Object terminal);
extern Lisp_Object Fx_display_mm_width (Lisp_Object terminal);
extern Lisp_Object Fx_display_mm_height (Lisp_Object terminal);
extern Lisp_Object Fx_display_screens (Lisp_Object terminal);
extern Lisp_Object Fx_display_planes (Lisp_Object terminal);
extern Lisp_Object Fx_display_color_cells (Lisp_Object terminal);
extern Lisp_Object Fx_display_visual_class (Lisp_Object terminal);
extern Lisp_Object Fx_display_backing_store (Lisp_Object terminal);
extern Lisp_Object Fx_display_save_under (Lisp_Object terminal);

extern struct ios_display_info *ios_term_init (void);
extern void ios_term_shutdown (int sig);

/* Implemented in iosterm.m, published in or needed from iosfns.m.  */
extern Lisp_Object ios_list_fonts (struct frame *f, Lisp_Object pattern,
                                   int size, int maxnames);
extern void ios_clear_frame (struct frame *f);

extern void ios_set_offset (struct frame *f, int xoff, int yoff,
                            int change_grav);

extern const char *ios_xlfd_to_fontname (const char *xlfd);

extern Lisp_Object ios_map_event_to_object (void);
#ifdef __OBJC__
extern Lisp_Object ios_string_from_pasteboard (UIPasteboard *pb);
extern void ios_string_to_pasteboard (UIPasteboard *pb, Lisp_Object str);
#endif
extern Lisp_Object ios_get_local_selection (Lisp_Object selection_name,
                                            Lisp_Object target_type);
extern void iosatoms_of_iosselect (void);
extern void ios_set_doc_edited (void);

extern bool
ios_defined_color (struct frame *f,
                   const char *name,
                   Emacs_Color *color_def, bool alloc,
                   bool makeIndex);

#ifdef __OBJC__
extern int ios_lisp_to_color (Lisp_Object color, UIColor **col);
extern const char *ios_get_pending_menu_title (void);
#endif

/* Implemented in iosfns.m, published in iosterm.m.  */
#ifdef __OBJC__
extern void ios_move_tooltip_to_touch_location (CGPoint);
#endif
extern void ios_implicitly_set_name (struct frame *f, Lisp_Object arg,
                                     Lisp_Object oldval);
extern void ios_set_scroll_bar_default_width (struct frame *f);
extern void ios_set_scroll_bar_default_height (struct frame *f);
extern void ios_change_tab_bar_height (struct frame *f, int height);
extern const char *ios_get_string_resource (void *_rdb,
                                            const char *name,
                                            const char *class);
extern void ios_free_frame_resources (struct frame *f);

/* C access to ObjC functionality.  */
extern void ios_release_object (void *obj);
extern void ios_retain_object (void *obj);
extern void *ios_alloc_autorelease_pool (void);
extern void ios_release_autorelease_pool (void *);
extern const char *ios_get_defaults_value (const char *key);
extern void ios_init_pool (void);
extern void ios_init_locale (void);

/* Defined in iosmenu.m.  */
extern Lisp_Object find_and_return_menu_selection (struct frame *f,
                                                   bool keymaps,
                                                   void *client_data);
extern Lisp_Object ios_popup_dialog (struct frame *, Lisp_Object header,
                                     Lisp_Object contents);

extern void ios_free_frame_resources (struct frame *);

extern const char *ios_relocate (const char *epath);
extern void syms_of_iosterm (void);
extern void syms_of_iosfns (void);
extern void syms_of_iosmenu (void);
extern void syms_of_iosselect (void);

/* From iosimage.m, needed in image.c.  */
struct image;
extern bool ios_can_use_native_image_api (Lisp_Object type);
extern void *ios_image_from_XBM (char *bits, int width, int height,
                                 unsigned long fg, unsigned long bg);
extern void *ios_image_for_XPM (int width, int height, int depth);
extern void *ios_image_from_file (Lisp_Object file);
extern bool ios_load_image (struct frame *f, struct image *img,
                            Lisp_Object spec_file, Lisp_Object spec_data);
extern int ios_image_width (void *img);
extern int ios_image_height (void *img);
extern void ios_image_set_size (void *img, int width, int height);
extern void ios_image_set_transform (void *img, double m[3][3]);
extern void ios_image_set_smoothing (void *img, bool smooth);
extern unsigned long ios_get_pixel (void *img, int x, int y);
extern void ios_put_pixel (void *img, int x, int y, unsigned long argb);
extern void ios_set_alpha (void *img, int x, int y, unsigned char a);

extern int ios_display_pixel_height (struct ios_display_info *);
extern int ios_display_pixel_width (struct ios_display_info *);
extern size_t ios_image_size_in_bytes (void *img);

/* Defined in iosterm.m.  */
extern float ios_antialias_threshold;
extern void ios_make_frame_visible (struct frame *f);
extern void ios_make_frame_invisible (struct frame *f);
extern void ios_iconify_frame (struct frame *f);
extern void ios_set_undecorated (struct frame *f, Lisp_Object new_value,
                                 Lisp_Object old_value);
extern void ios_set_parent_frame (struct frame *f, Lisp_Object new_value,
                                  Lisp_Object old_value);
extern void ios_set_no_focus_on_map (struct frame *f, Lisp_Object new_value,
                                     Lisp_Object old_value);
extern void ios_set_no_accept_focus (struct frame *f, Lisp_Object new_value,
                                     Lisp_Object old_value);
extern void ios_set_z_group (struct frame *f, Lisp_Object new_value,
                             Lisp_Object old_value);
extern void ios_set_appearance (struct frame *f, Lisp_Object new_value,
                                Lisp_Object old_value);

/* System appearance (dark/light mode) support.  */
extern void ios_handle_appearance_change (bool is_dark);
extern void ios_init_system_appearance (void);

/* Background blur support (iOS equivalent of ns-background-blur).  */
extern void ios_set_background_blur (struct frame *f, Lisp_Object new_value,
                                     Lisp_Object old_value);
extern void ios_update_background_blur (struct frame *f);

/* Per-element alpha support (iOS equivalent of ns-alpha-elements).  */
extern void ios_set_alpha_elements (struct frame *f, Lisp_Object new_value,
                                    Lisp_Object old_value);
extern bool ios_alpha_element_enabled (struct frame *f, Lisp_Object element);

extern int ios_select (int nfds, fd_set *readfds, fd_set *writefds,
                       fd_set *exceptfds, struct timespec *timeout,
                       sigset_t *sigmask);
#ifdef HAVE_PTHREAD
extern void ios_run_loop_break (void);
#endif
extern unsigned long ios_get_rgb_color (struct frame *f,
                                        float r, float g, float b, float a);

struct input_event;
extern void ios_init_events (struct input_event *);
extern void ios_finish_events (void);

extern double ios_frame_scale_factor (struct frame *);

extern frame_parm_handler ios_frame_parm_handlers[];

extern void mark_iosterm (void);

#define MINWIDTH 10
#define MINHEIGHT 10

/* Screen max coordinate.  */
#define SCREENMAX 16000

#define IOS_SCROLL_BAR_WIDTH_DEFAULT     [EmacsScroller scrollerWidth]
#define IOS_SCROLL_BAR_HEIGHT_DEFAULT    [EmacsScroller scrollerHeight]

/* Selection colors.  */
#define IOS_SELECTION_BG_COLOR_DEFAULT	@"systemBlueColor"
#define IOS_SELECTION_FG_COLOR_DEFAULT	@"labelColor"

#define RESIZE_HANDLE_SIZE 12

/* Little utility macros.  */
#define IN_BOUND(min, x, max) (((x) < (min)) \
                                ? (min) : (((x)>(max)) ? (max) : (x)))
#define SCREENMAXBOUND(x) IN_BOUND (-SCREENMAX, x, SCREENMAX)


/* ==========================================================================

   iOS UIKit version and feature compatibility

   ========================================================================== */

/* UIKit key modifier constants (iOS 13.4+).  */
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 130400
#define IOS_HAS_HARDWARE_KEYBOARD_MODIFIERS 1
#else
#define IOS_HAS_HARDWARE_KEYBOARD_MODIFIERS 0
#endif

/* Context menu support (iOS 13+).  */
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 130000
#define IOS_HAS_CONTEXT_MENUS 1
#else
#define IOS_HAS_CONTEXT_MENUS 0
#endif

/* Pointer interaction support (iOS 13.4+).  */
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 130400
#define IOS_HAS_POINTER_INTERACTION 1
#else
#define IOS_HAS_POINTER_INTERACTION 0
#endif

/* Scene-based lifecycle (iOS 13+).  */
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 130000
#define IOS_HAS_SCENE_LIFECYCLE 1
#else
#define IOS_HAS_SCENE_LIFECYCLE 0
#endif


/* ==========================================================================

   UIWindow / UIViewController Connection Functions
   
   These functions are only available from Objective-C code.

   ========================================================================== */

#ifdef __OBJC__
/* Set the main UIWindow from the app delegate/scene delegate.  */
extern void ios_set_main_window (UIWindow *window);

/* Get the main UIWindow.  */
extern UIWindow *ios_get_main_window (void);
#endif /* __OBJC__ */

/* Connect an Emacs frame to the UIWindow.  */
extern void ios_connect_frame_to_window (struct frame *f);

/* Initialize iOS paths from bundle.  Must be called before init_lread.  */
extern void ios_init_paths (void);

/* Override Emacs path variables after syms_of_lread.  */
extern void ios_override_path_variables (void);
extern void ios_debug_log (const char *msg);

/* Get the pdumper fingerprint as a malloc'd hex string.
   Used by main.m to find the correct dump file.  */
extern char *ios_get_fingerprint (void);



/* ==========================================================================

   Color conversion macros

   ========================================================================== */

#define RGB_TO_ULONG(r, g, b)   (((r) << 16) | ((g) << 8) | (b))
#define RED_FROM_ULONG(color)   (((color) >> 16) & 0xff)
#define GREEN_FROM_ULONG(color) (((color) >> 8) & 0xff)
#define BLUE_FROM_ULONG(color)  ((color) & 0xff)


/* ==========================================================================

   iOS Event Queue (modeled after Android port)
   
   Event types are defined in iosgui.h.

   ========================================================================== */

#include "iosgui.h"

/* Configure (resize) event.  */
struct ios_configure_event
{
  enum ios_event_type type;
  struct frame *frame;
  int width;
  int height;
};

/* Expose (redraw) event.  */
struct ios_expose_event
{
  enum ios_event_type type;
  struct frame *frame;
};

/* Generic event container.  */
union ios_event
{
  enum ios_event_type type;
  struct ios_configure_event xconfigure;
  struct ios_expose_event xexpose;
};

/* Event queue functions.  */
extern void ios_write_event (union ios_event *event);
extern int ios_pending (void);
extern bool ios_next_event (union ios_event *event_return);
extern void ios_wait_event (void);


/* ==========================================================================
   Single dispatch system header
   ========================================================================== */

#include "iosdispatch.h"

#endif  /* HAVE_IOS */

#endif  /* EMACS_IOSTERM_H */
