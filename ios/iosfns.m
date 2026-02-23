/* Functions for the iOS/UIKit window system.

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

#include <config.h>

#ifdef HAVE_IOS

#include <math.h>
#include <c-strcase.h>

#include "lisp.h"
#include "blockinput.h"
#include "dispextern.h"
#include "iosterm.h"
#include "window.h"
#include "character.h"
#include "buffer.h"
#include "keyboard.h"
#include "termhooks.h"
#include "fontset.h"
#include "font.h"
#include "macfont.h"
#include "iosdispatch.h"

#import <UIKit/UIKit.h>

extern NSString *ios_app_name;
extern void ios_clear_frame (struct frame *f);

static void ios_set_name (struct frame *, Lisp_Object, Lisp_Object);
/* ==========================================================================
   Single dispatch system implementation
   ========================================================================== */

ios_command_entry *ios_dispatch_table = NULL;
int ios_dispatch_count = 0;
int ios_dispatch_capacity = 0;

void
ios_dispatch_init(void)
{
  if (ios_dispatch_table == NULL) {
    ios_dispatch_capacity = 32;
    ios_dispatch_table = xzalloc(sizeof(ios_command_entry) * ios_dispatch_capacity);
    ios_dispatch_count = 0;
  }
}

void
ios_dispatch_register(ios_command_id cmd_id, const char *name,
                      ios_dispatch_handler handler,
                      Lisp_Object (*elisp_func)(Lisp_Object))
{
  ios_dispatch_init();

  /* Ensure capacity */
  if (ios_dispatch_count >= ios_dispatch_capacity) {
    int new_capacity = ios_dispatch_capacity * 2;
    ios_command_entry *new_table = xrealloc(ios_dispatch_table,
                                             sizeof(ios_command_entry) * new_capacity);
    ios_dispatch_table = new_table;
    ios_dispatch_capacity = new_capacity;
  }

  /* Check if already registered (update existing) */
  for (int i = 0; i < ios_dispatch_count; i++) {
    if (ios_dispatch_table[i].command_id == cmd_id) {
      ios_dispatch_table[i].handler = handler;
      ios_dispatch_table[i].elisp_func = elisp_func;
      return;
    }
  }

  /* Add new entry */
  ios_dispatch_table[ios_dispatch_count].name = xstrdup(name);
  ios_dispatch_table[ios_dispatch_count].command_id = cmd_id;
  ios_dispatch_table[ios_dispatch_count].handler = handler;
  ios_dispatch_table[ios_dispatch_count].elisp_func = elisp_func;
  ios_dispatch_count++;
}

ios_command_entry *
ios_dispatch_lookup(int command_id)
{
  if (ios_dispatch_table == NULL) return NULL;

  for (int i = 0; i < ios_dispatch_count; i++) {
    if (ios_dispatch_table[i].command_id == command_id) {
      return &ios_dispatch_table[i];
    }
  }
  return NULL;
}

Lisp_Object
ios_dispatch_command(int command_id, Lisp_Object args)
{
  ios_command_entry *entry = ios_dispatch_lookup(command_id);

  if (entry == NULL) {
    return Fsignal(Qerror, list2(build_string("Unknown iOS command"), make_fixnum(command_id)));
  }

  /* If a custom handler is registered, use it */
  if (entry->handler != NULL) {
    return entry->handler(args);
  }

  /* Otherwise, call the elisp function directly */
  if (entry->elisp_func != NULL) {
    return entry->elisp_func(args);
  }

  return Fsignal(Qerror, list2(build_string("iOS command has no handler"),
                               build_string(entry->name)));
}


/* ==========================================================================

   Display information

   ========================================================================== */

static struct ios_display_info *
check_ios_display_info (Lisp_Object frame)
{
  if (NILP (frame)) return ios_display_list;
  if (XFRAME (frame)->output_method != output_ios) error ("Not an iOS frame");
  return FRAME_DISPLAY_INFO (XFRAME (frame));
}

struct ios_display_info *
check_x_display_info (Lisp_Object frame)
{
  return check_ios_display_info (frame);
}


/* ==========================================================================

   iOS-specific Lisp functions

   ========================================================================== */

DEFUN ("ios-safe-area-insets", Fios_safe_area_insets, Sios_safe_area_insets, 0, 1, 0,
       doc: /* Return the safe area insets for FRAME.  */)
  (Lisp_Object frame)
{
  struct frame *f = decode_window_system_frame (frame);
  return list4 (make_float (f->output_data.ios->safe_area_top),
                make_float (f->output_data.ios->safe_area_left),
                make_float (f->output_data.ios->safe_area_bottom),
                make_float (f->output_data.ios->safe_area_right));
}

DEFUN ("ios-keyboard-height", Fios_keyboard_height, Sios_keyboard_height, 0, 0, 0, doc: /* Keyboard. */)
  (void) { return make_float (0.0); }

DEFUN ("ios-system-appearance", Fios_system_appearance, Sios_system_appearance, 0, 0, 0, doc: /* Appearance. */)
  (void)
{
  __block Lisp_Object appearance = Qlight;
  dispatch_sync (dispatch_get_main_queue (), ^{
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
      appearance = Qdark;
  });
  return appearance;
}

DEFUN ("ios-haptic-feedback", Fios_haptic_feedback, Sios_haptic_feedback, 0, 1, 0, doc: /* Haptic. */)
  (Lisp_Object type) { return Qnil; }


/* ==========================================================================

   Display Metrics

   ========================================================================== */

DEFUN ("xw-display-color-p", Fxw_display_color_p, Sxw_display_color_p, 0, 1, 0, doc: /* Color. */)
  (Lisp_Object terminal) { return Qt; }

DEFUN ("xw-color-defined-p", Fxw_color_defined_p, Sxw_color_defined_p, 1, 2, 0,
       doc: /* Return t if COLOR is a valid color name on FRAME.
If FRAME is nil, use the selected frame.  */)
  (Lisp_Object color, Lisp_Object frame)
{
  Emacs_Color col;
  struct frame *f = decode_window_system_frame (frame);

  CHECK_STRING (color);

  return ios_defined_color (f, SSDATA (color), &col, false, false) ? Qt : Qnil;
}

DEFUN ("xw-color-values", Fxw_color_values, Sxw_color_values, 1, 2, 0,
       doc: /* Return a list of RGB color values for COLOR on FRAME.
COLOR should be a color name or a string representing a color.
If FRAME is nil, use the selected frame.
Returns a list (RED GREEN BLUE) with each value in the range 0-65535.  */)
  (Lisp_Object color, Lisp_Object frame)
{
  Emacs_Color col;
  struct frame *f = decode_window_system_frame (frame);

  CHECK_STRING (color);

  if (ios_defined_color (f, SSDATA (color), &col, false, false))
    return list3i (col.red, col.green, col.blue);
  else
    return Qnil;
}

DEFUN ("x-display-grayscale-p", Fx_display_grayscale_p, Sx_display_grayscale_p, 0, 1, 0, doc: /* Gray. */)
  (Lisp_Object terminal) { return Qnil; }

DEFUN ("x-display-pixel-width", Fx_display_pixel_width, Sx_display_pixel_width, 0, 1, 0, doc: /* Width. */)
  (Lisp_Object terminal)
{
  __block int width = 1032;
  dispatch_sync (dispatch_get_main_queue (), ^{ width = (int)(UIScreen.mainScreen.bounds.size.width * UIScreen.mainScreen.scale); });
  return make_fixnum (width);
}

DEFUN ("x-display-pixel-height", Fx_display_pixel_height, Sx_display_pixel_height, 0, 1, 0, doc: /* Height. */)
  (Lisp_Object terminal)
{
  __block int height = 1376;
  dispatch_sync (dispatch_get_main_queue (), ^{ height = (int)(UIScreen.mainScreen.bounds.size.height * UIScreen.mainScreen.scale); });
  return make_fixnum (height);
}

DEFUN ("x-display-mm-width", Fx_display_mm_width, Sx_display_mm_width, 0, 1, 0, doc: /* MM Width. */)
  (Lisp_Object terminal) { return make_fixnum (200); }

DEFUN ("x-display-mm-height", Fx_display_mm_height, Sx_display_mm_height, 0, 1, 0, doc: /* MM Height. */)
  (Lisp_Object terminal) { return make_fixnum (280); }

DEFUN ("x-display-screens", Fx_display_screens, Sx_display_screens, 0, 1, 0, doc: /* Screens. */)
  (Lisp_Object terminal) { return make_fixnum (1); }

DEFUN ("x-display-planes", Fx_display_planes, Sx_display_planes, 0, 1, 0, doc: /* Planes. */)
  (Lisp_Object terminal) { return make_fixnum (24); }

DEFUN ("x-display-color-cells", Fx_display_color_cells, Sx_display_color_cells, 0, 1, 0, doc: /* Cells. */)
  (Lisp_Object terminal) { return make_fixnum (16777216); }

DEFUN ("x-display-visual-class", Fx_display_visual_class, Sx_display_visual_class, 0, 1, 0, doc: /* Visual. */)
  (Lisp_Object terminal) { return Qtrue_color; }

DEFUN ("x-display-backing-store", Fx_display_backing_store, Sx_display_backing_store, 0, 1, 0, doc: /* Backing. */)
  (Lisp_Object terminal) { return Qalways; }

DEFUN ("x-display-save-under", Fx_display_save_under, Sx_display_save_under, 0, 1, 0, doc: /* Save. */)
  (Lisp_Object terminal) { return Qt; }

DEFUN ("x-server-vendor", Fx_server_vendor, Sx_server_vendor, 0, 1, 0, doc: /* Vendor. */)
  (Lisp_Object terminal) { return build_string ("Apple Inc."); }

DEFUN ("x-server-version", Fx_server_version, Sx_server_version, 0, 1, 0, doc: /* Version. */)
  (Lisp_Object terminal) { return list3 (make_fixnum (1), make_fixnum (0), make_fixnum (0)); }

DEFUN ("x-server-max-request-size", Fx_server_max_request_size, Sx_server_max_request_size, 0, 1, 0, doc: /* Max. */)
  (Lisp_Object terminal) { return make_fixnum (1000000); }


/* ==========================================================================

   Frame parameter setting functions

   ========================================================================== */

void
ios_set_foreground_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval)
{
  struct ios_output *output = f->output_data.ios;
  Emacs_Color col;
  if (ios_defined_color (f, SSDATA (arg), &col, true, false))
    {
      if (output->foreground_color) [output->foreground_color release];
      output->foreground_color = [[UIColor colorWithUnsignedLong:col.pixel] retain];
      if (FRAME_VISIBLE_P (f)) SET_FRAME_GARBAGED (f);
    }
}

void
ios_set_background_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval)
{
  if (!f)
    return;
  
  struct ios_output *output = f->output_data.ios;
  if (!output)
    return;
  
  NSLog(@"ios_set_background_color: arg=%s", STRINGP(arg) ? SSDATA(arg) : "(not string)");
    
  Emacs_Color col;
  if (ios_defined_color (f, SSDATA (arg), &col, true, false))
    {
      NSLog(@"ios_set_background_color: color resolved to pixel=0x%lx", col.pixel);
      
      if (output->background_color) [output->background_color release];
      output->background_color = [[UIColor colorWithUnsignedLong:col.pixel] retain];
      
      /* Also update last_face_background so ios_update_end doesn't fight with us.  */
      output->last_face_background = col.pixel;
      
      /* Update the default face background to match (if face system is ready).
         FRAME_FACE_CACHE must exist before we can access FRAME_DEFAULT_FACE.  */
      if (FRAME_FACE_CACHE (f))
        {
          struct face *face = FRAME_DEFAULT_FACE (f);
          if (face)
            {
              face->background = col.pixel;
              update_face_from_frame_parameter (f, Qbackground_color, arg);
            }
        }
      
      if (output->view)
        {
          EmacsView *view = output->view;
          UIColor *bgColor = output->background_color;
          /* Clear the offscreen buffer with the new background color.
             This must happen before setNeedsDisplay triggers a redraw.  */
          [view clearOffscreenWithBackgroundColor];
          dispatch_async (dispatch_get_main_queue (), ^{
            [view setBackgroundColor:bgColor];
            [view setNeedsDisplay];
          });
        }
      
      if (FRAME_VISIBLE_P (f))
        {
          SET_FRAME_GARBAGED (f);
          /* Only call ios_clear_frame if view exists and is ready.  */
          if (output->view)
            ios_clear_frame (f);
        }
    }
}

void
ios_set_cursor_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval)
{
  struct ios_output *output = f->output_data.ios;
  Emacs_Color col;
  if (ios_defined_color (f, SSDATA (arg), &col, true, false))
    {
      if (output->cursor_color) [output->cursor_color release];
      output->cursor_color = [[UIColor colorWithUnsignedLong:col.pixel] retain];
      if (FRAME_VISIBLE_P (f)) gui_update_cursor (f, false);
    }
}

void ios_set_cursor_type (struct frame *f, Lisp_Object arg, Lisp_Object oldval) { set_frame_cursor_types (f, arg); }
void ios_set_border_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval) {}
void ios_set_child_frame_border_width (struct frame *f, Lisp_Object arg, Lisp_Object oldval) {}
void ios_set_internal_border_width (struct frame *f, Lisp_Object arg, Lisp_Object oldval) {}
void ios_set_mouse_color (struct frame *f, Lisp_Object arg, Lisp_Object oldval) {}
void ios_set_tab_bar_lines (struct frame *f, Lisp_Object arg, Lisp_Object oldval) {}
void ios_set_tool_bar_lines (struct frame *f, Lisp_Object arg, Lisp_Object oldval) {}

void
ios_set_fontsize (struct frame *f, Lisp_Object arg, Lisp_Object oldval)
{
  if (NILP (arg)) return;
  int size = XFIXNUM (arg);
  if (size < 1) size = 1;
  if (f->output_data.ios->fontsize != size) { f->output_data.ios->fontsize = size; SET_FRAME_GARBAGED (f); }
}

void ios_set_icon_name (struct frame *f, Lisp_Object arg, Lisp_Object oldval) { if (NILP (arg)) arg = build_string (""); fset_icon_name (f, arg); }
void ios_set_icon_type (struct frame *f, Lisp_Object arg, Lisp_Object oldval) {}

static void
ios_set_name (struct frame *f, Lisp_Object arg, Lisp_Object oldval)
{
  if (NILP (arg)) arg = build_string ("Emacs");
  fset_name (f, arg);
}

void ios_explicitly_set_name (struct frame *f, Lisp_Object arg, Lisp_Object oldval) { ios_set_name (f, arg, oldval); }

void
ios_set_title (struct frame *f, Lisp_Object arg, Lisp_Object oldval)
{
  if (NILP (arg)) arg = build_string ("Emacs");
  fset_title (f, arg);
}


/* ==========================================================================

   Frame creation

   ========================================================================== */

static void
unwind_create_frame (Lisp_Object frame)
{
  struct frame *f = XFRAME (frame);
  if (!FRAME_LIVE_P (f)) return;
  if (NILP (Fmemq (frame, Vframe_list))) { free_glyphs (f); }
}

DEFUN ("x-create-frame", Fx_create_frame, Sx_create_frame, 1, 1, 0,
       doc: /* Create a new iOS frame.  */)
  (Lisp_Object parms)
{
  struct frame *f;
  Lisp_Object lisp_frame;
  struct ios_display_info *dpyinfo;
  specpdl_ref count = SPECPDL_INDEX ();

  dpyinfo = check_ios_display_info (Qnil);
  parms = Fcopy_alist (parms);

  f = make_frame (true);
  f->output_method = output_ios;
  f->terminal = dpyinfo->terminal;
  f->output_data.ios = xzalloc (sizeof (struct ios_output));
  f->output_data.ios->display_info = dpyinfo;
  
  XSETFRAME (lisp_frame, f);
  record_unwind_protect (unwind_create_frame, lisp_frame);

  /* Get screen size in points (not pixels).  */
  __block CGFloat screenWidthPts = 516, screenHeightPts = 688;
  dispatch_sync (dispatch_get_main_queue (), ^{
    UIScreen *screen = [UIScreen mainScreen];
    screenWidthPts = screen.bounds.size.width;
    screenHeightPts = screen.bounds.size.height;
  });
  
  f->output_data.ios->fontsize = 14;
  
  /* Initialize last_face_background to an impossible value so the first
     update will always detect a "change" and set up colors properly.  */
  f->output_data.ios->last_face_background = 0xDEADBEEF;

  mac_register_font_driver (f);
  
  /* Use direct symbols.  */
  gui_default_parameter (f, parms, Qfont_backend, Qnil, "font-backend", "FontBackend", RES_TYPE_SYMBOL);
  gui_default_parameter (f, parms, Qfont, build_string ("Courier"), "font", "Font", RES_TYPE_STRING);
  gui_default_parameter (f, parms, Qforeground_color, build_string ("black"), "foreground", "Foreground", RES_TYPE_STRING);
  gui_default_parameter (f, parms, Qbackground_color, build_string ("white"), "background", "Background", RES_TYPE_STRING);
  gui_default_parameter (f, parms, Qcursor_color, build_string ("white"), "cursorColor", "CursorColor", RES_TYPE_STRING);
  gui_default_parameter (f, parms, Qmouse_color, build_string ("white"), "mouseColor", "MouseColor", RES_TYPE_STRING);
  gui_default_parameter (f, parms, Qborder_color, build_string ("black"), "borderColor", "BorderColor", RES_TYPE_STRING);

  init_frame_faces (f);

  /* Now that fonts are set up, calculate frame size in columns and lines
     to fill the screen.  UIKit uses points, and Emacs uses points for
     its internal geometry (FRAME_COLUMN_WIDTH etc. are in points).
     
     Calculate how many columns/lines fit in the screen, then convert
     back to text pixel dimensions for adjust_frame_size.  */
  int col_width = FRAME_COLUMN_WIDTH (f);
  int line_height = FRAME_LINE_HEIGHT (f);
  
  /* Safety check - use defaults if font metrics not set yet.  */
  if (col_width <= 0) col_width = 8;
  if (line_height <= 0) line_height = 16;
  
  int cols = (int)(screenWidthPts / col_width);
  int lines = (int)(screenHeightPts / line_height);
  
  /* Ensure minimum size.  */
  if (cols < 10) cols = 10;
  if (lines < 4) lines = 4;
  
  int text_width = cols * col_width;
  int text_height = lines * line_height;
  
  NSLog(@"ios_create_frame: screen=%.0fx%.0f pts, col_width=%d line_height=%d, cols=%d lines=%d, text=%dx%d",
        screenWidthPts, screenHeightPts, col_width, line_height, cols, lines, text_width, text_height);

  /* Set min_width/min_height to avoid Lisp call during early frame init.  */
  store_frame_param (f, Qmin_width, make_fixnum (1));
  store_frame_param (f, Qmin_height, make_fixnum (1));
  
  adjust_frame_size (f, text_width, text_height, 5, true, Qnil);
  adjust_frame_glyphs (f);
  
  NSLog(@"ios_create_frame: after adjust_frame_size: FRAME_PIXEL=%dx%d TEXT=%dx%d COLS=%d LINES=%d",
        FRAME_PIXEL_WIDTH(f), FRAME_PIXEL_HEIGHT(f),
        FRAME_TEXT_WIDTH(f), FRAME_TEXT_HEIGHT(f),
        FRAME_COLS(f), FRAME_LINES(f));

  block_input ();
  f->output_data.ios->view = [EmacsView createFrameView:f];
  unblock_input ();

  /* ios_display_info does not have a reference_count.  */
  f->terminal->reference_count++;

  /* It is now ok to make the frame official even if we get an error
     below.  The frame needs to be on Vframe_list or making it visible
     won't work.  */
  Vframe_list = Fcons (lisp_frame, Vframe_list);

  ios_connect_frame_to_window (f);
  
  /* Make the frame visible now.  */
  ios_make_frame_visible (f);
  
  /* Force a full frame redraw to clear the garbaged flag and 
     trigger initial drawing.  This calls update_begin/update_end.  */
  NSLog(@"ios_create_frame: glyphs_initialized_p=%d before Fredraw_frame", f->glyphs_initialized_p);
  if (f->glyphs_initialized_p)
    {
      NSLog(@"ios_create_frame: calling Fredraw_frame to trigger initial redraw");
      Fredraw_frame (lisp_frame);
      NSLog(@"ios_create_frame: Fredraw_frame returned");
    }
  else
    {
      NSLog(@"ios_create_frame: glyphs NOT initialized, skipping Fredraw_frame");
    }
  
  /* Clear window list cache to make sure windows on this frame appear
     in calls to next-window and similar functions.  */
  Vwindow_list = Qnil;
  
  /* Signal that bootstrap is complete - the frame is ready.  */
  extern void ios_report_bootstrap_complete (void);
  ios_report_bootstrap_complete ();
  
  return unbind_to (count, lisp_frame);
}

DEFUN ("x-open-connection", Fx_open_connection, Sx_open_connection, 1, 3, 0, doc: /* Open. */) (Lisp_Object display, Lisp_Object xrm_string, Lisp_Object must_succeed) { return Qnil; }
DEFUN ("x-close-connection", Fx_close_connection, Sx_close_connection, 1, 1, 0, doc: /* Close. */) (Lisp_Object display) { return Qnil; }
DEFUN ("x-display-list", Fx_display_list, Sx_display_list, 0, 0, 0, doc: /* List. */) (void) { Lisp_Object result = Qnil; struct ios_display_info *dpyinfo; for (dpyinfo = ios_display_list; dpyinfo; dpyinfo = dpyinfo->next) result = Fcons (XCAR (dpyinfo->name_list_element), result); return result; }
DEFUN ("x-show-tip", Fx_show_tip, Sx_show_tip, 1, 6, 0, doc: /* Tip. */) (Lisp_Object string, Lisp_Object frame, Lisp_Object parms, Lisp_Object dx, Lisp_Object dy, Lisp_Object timeout) { return Qnil; }
DEFUN ("x-hide-tip", Fx_hide_tip, Sx_hide_tip, 0, 0, 0, doc: /* Hide. */) (void) { return Qnil; }
DEFUN ("ios-get-connection", Fios_get_connection, Sios_get_connection, 0, 0, 0, doc: /* Conn. */) (void) { Lisp_Object terminal = Qnil; if (ios_display_list) XSETTERMINAL (terminal, ios_display_list->terminal); return terminal; }

/* ==========================================================================
   Selection (Clipboard) support
   ========================================================================== */
DEFUN ("ios-own-selection-internal", Fios_own_selection_internal, Sios_own_selection_internal, 2, 2, 0, doc: /* Own. */) (Lisp_Object selection, Lisp_Object value) { if (STRINGP (value)) { NSString *str = [NSString stringWithUTF8String:SSDATA (value)]; dispatch_async (dispatch_get_main_queue (), ^{ [[UIPasteboard generalPasteboard] setString:str]; }); } return value; }
DEFUN ("ios-disown-selection-internal", Fios_disown_selection_internal, Sios_disown_selection_internal, 1, 1, 0, doc: /* Disown. */) (Lisp_Object selection) { dispatch_async (dispatch_get_main_queue (), ^{ [[UIPasteboard generalPasteboard] setString:@""]; }); return Qnil; }
DEFUN ("ios-selection-exists-p", Fios_selection_exists_p, Sios_selection_exists_p, 0, 1, 0, doc: /* Exists. */) (Lisp_Object selection) { __block BOOL hasContent = NO; dispatch_sync (dispatch_get_main_queue (), ^{ hasContent = [[UIPasteboard generalPasteboard] hasStrings]; }); return hasContent ? Qt : Qnil; }
DEFUN ("ios-selection-owner-p", Fios_selection_owner_p, Sios_selection_owner_p, 0, 1, 0, doc: /* Owner. */) (Lisp_Object selection) { return Qnil; }
DEFUN ("ios-get-selection", Fios_get_selection, Sios_get_selection, 1, 2, 0, doc: /* Get. */) (Lisp_Object selection, Lisp_Object target_type) { __block NSString *str = nil; dispatch_sync (dispatch_get_main_queue (), ^{ str = [[UIPasteboard generalPasteboard] string]; }); if (str && [str length] > 0) return build_string ([str UTF8String]); return Qnil; }

/* ==========================================================================
   Symbol initialization
   ========================================================================== */
void syms_of_iosfns (void)
{
  defsubr (&Sx_create_frame);
  defsubr (&Sx_open_connection);
  defsubr (&Sx_close_connection);
  defsubr (&Sx_display_list);
  defsubr (&Sx_display_screens);
  defsubr (&Sx_display_mm_height);
  defsubr (&Sx_display_mm_width);
  defsubr (&Sx_display_pixel_width);
  defsubr (&Sx_display_pixel_height);
  defsubr (&Sx_display_color_cells);
  defsubr (&Sx_display_planes);
  defsubr (&Sx_server_vendor);
  defsubr (&Sx_server_version);
  defsubr (&Sx_server_max_request_size);
  defsubr (&Sx_display_backing_store);
  defsubr (&Sx_display_visual_class);
  defsubr (&Sx_display_save_under);
  defsubr (&Sxw_display_color_p);
  defsubr (&Sxw_color_defined_p);
  defsubr (&Sxw_color_values);
  defsubr (&Sx_display_grayscale_p);
  defsubr (&Sx_show_tip);
  defsubr (&Sx_hide_tip);
  defsubr (&Sios_get_connection);
  defsubr (&Sios_safe_area_insets);
  defsubr (&Sios_keyboard_height);
  defsubr (&Sios_system_appearance);
  defsubr (&Sios_haptic_feedback);
  defsubr (&Sios_own_selection_internal);
  defsubr (&Sios_disown_selection_internal);
  defsubr (&Sios_selection_exists_p);
  defsubr (&Sios_selection_owner_p);
  defsubr (&Sios_get_selection);
  /* iOS-specific symbols only - standard frame symbols are already
     defined in frame.c, xfaces.c, textprop.c.  */
  DEFSYM (Qios_appearance, "ios-appearance");
  DEFSYM (Qfontsize, "fontsize");
  DEFSYM (Qtrue_color, "true-color");
  DEFSYM (Qalways, "always");
  DEFSYM (Qdark, "dark");
  DEFSYM (Qlight, "light");
  /* DO NOT redefine Qfont, Qfont_backend, Qforeground_color, etc.
     They are standard Emacs symbols already defined elsewhere.  */

  /* Initialize dispatch system */
  ios_dispatch_init();
}
#endif /* HAVE_IOS */
