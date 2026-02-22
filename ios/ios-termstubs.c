/* ios-termstubs.c -- Stub terminfo/termcap functions for iOS

   Copyright (C) 2026 Free Software Foundation, Inc.

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

/* iOS GUI-only Emacs doesn't need terminfo/termcap functions.
   These stubs allow term.c to compile and link without ncurses.
   Terminal output is handled by the UIKit GUI layer instead.  */

#include <config.h>

#ifdef HAVE_IOS

#include <stddef.h>

/* tputs - Output a terminal capability string.  */
int
tputs (const char *str, int affcnt, int (*putc_func)(int))
{
  /* No-op on iOS - terminal output handled by UIKit.  */
  return 0;
}

/* tparm - Substitute parameters into a capability string.  */
char *
tparm (const char *cap, ...)
{
  /* Return empty string - no terminal parameters on iOS.  */
  return "";
}

/* tigetstr - Get a string terminal capability.  */
char *
tigetstr (const char *capname)
{
  /* Return NULL (not found) - no terminfo on iOS.  */
  return NULL;
}

/* tigetflag - Get a boolean terminal capability.  */
int
tigetflag (const char *capname)
{
  /* Return -1 (not found) - no terminfo on iOS.  */
  return -1;
}

/* tigetnum - Get a numeric terminal capability.  */
int
tigetnum (const char *capname)
{
  /* Return -1 (not found) - no terminfo on iOS.  */
  return -1;
}

/* setupterm - Set up terminal.  */
int
setupterm (const char *term, int fd, int *errret)
{
  /* Return -1 (failure) - no terminal setup on iOS.  */
  if (errret)
    *errret = -1;
  return -1;
}

/* set_curterm - Set the current terminal.  */
void *
set_curterm (void *term)
{
  /* No-op on iOS.  */
  return NULL;
}

/* del_curterm - Delete a terminal.  */
int
del_curterm (void *term)
{
  /* No-op on iOS.  */
  return 0;
}

/* ============== cm.c stubs ============== */

/* Cursor motion stubs - not needed for iOS GUI.  */

int cost = 0;   /* Cost accumulator.  */
int PC = 0;     /* Pad character.  */

void
Wcm_init (void *tty)
{
  /* No-op on iOS.  */
}

void
Wcm_clear (void *tty)
{
  /* No-op on iOS.  */
}

int
cmputc (int c)
{
  /* No-op on iOS.  */
  return c;
}

void
cmcheckmagic (void *tty)
{
  /* No-op on iOS.  */
}

void
cmcostinit (void *tty)
{
  /* No-op on iOS.  */
}

void
cmgoto (void *tty, int row, int col)
{
  /* No-op on iOS.  */
}

/* current_tty is referenced by term.c */
void *current_tty = NULL;

/* ============== Classic termcap stubs (tget*) ============== */

int
tgetent (char *bp, const char *name)
{
  /* Return 0 (not found) - no termcap on iOS.  */
  return 0;
}

int
tgetflag (const char *id)
{
  /* Return 0 (false) - no termcap on iOS.  */
  return 0;
}

int
tgetnum (const char *id)
{
  /* Return -1 (not found) - no termcap on iOS.  */
  return -1;
}

char *
tgetstr (const char *id, char **area)
{
  /* Return NULL (not found) - no termcap on iOS.  */
  return NULL;
}

/* evalcost is used by term.c for cost calculations.  */
int
evalcost (int c)
{
  return c;
}

/* NOTE: mac_register_font_driver is NOT stubbed here because
   macfont.o is now included in the iOS build (via IOS_OBJC_OBJ
   in configure.ac). The real implementation in macfont.m provides
   CoreText-based font rendering for iOS.  */

#endif /* HAVE_IOS */
