/**************************************************************************/
/*  dummy.cpp                                                             */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

extern void register_dynamic_symbol(char *name, void *address);
extern void add_ios_init_callback(void (*cb)());
extern "C" void godot_gdnative_init(void);
extern "C" void godot_gdnative_terminate(void) __attribute__((weak));
extern "C" void godot_nativescript_init(void) __attribute__((weak));
extern "C" void godot_nativescript_frame(void) __attribute__((weak));
extern "C" void godot_nativescript_thread_enter(void) __attribute__((weak));
extern "C" void godot_nativescript_thread_exit(void) __attribute__((weak));
extern "C" void godot_gdnative_singleton(void) __attribute__((weak));
void godot_init() {
  if (&godot_gdnative_init) register_dynamic_symbol((char *)"godot_gdnative_init", (void *)godot_gdnative_init);
  if (&godot_gdnative_terminate) register_dynamic_symbol((char *)"godot_gdnative_terminate", (void *)godot_gdnative_terminate);
  if (&godot_nativescript_init) register_dynamic_symbol((char *)"godot_nativescript_init", (void *)godot_nativescript_init);
  if (&godot_nativescript_frame) register_dynamic_symbol((char *)"godot_nativescript_frame", (void *)godot_nativescript_frame);
  if (&godot_nativescript_thread_enter) register_dynamic_symbol((char *)"godot_nativescript_thread_enter", (void *)godot_nativescript_thread_enter);
  if (&godot_nativescript_thread_exit) register_dynamic_symbol((char *)"godot_nativescript_thread_exit", (void *)godot_nativescript_thread_exit);
  if (&godot_gdnative_singleton) register_dynamic_symbol((char *)"godot_gdnative_singleton", (void *)godot_gdnative_singleton);
}
struct godot_struct {godot_struct() {add_ios_init_callback(godot_init);}};
godot_struct godot_struct_instance;

// Godot Plugins
void godot_ios_plugins_initialize();
void godot_ios_plugins_deinitialize();
// Exported Plugins

// Use Plugins
void godot_ios_plugins_initialize() {
}

void godot_ios_plugins_deinitialize() {
}


