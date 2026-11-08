static EmeraldUiWindow *emerald_ui_window_entry(int32_t handle) {
    if (handle <= 0 || handle > EMERALD_UI_MAX_WINDOWS) {
        return NULL;
    }

    EmeraldUiWindow *entry = &emerald_ui_windows[handle - 1];
    return entry->used ? entry : NULL;
}

static int32_t emerald_ui_store_window(EmeraldString *title, int32_t width, int32_t height) {
    int index = 0;

    while (index < EMERALD_UI_MAX_WINDOWS) {
        EmeraldUiWindow *entry = &emerald_ui_windows[index];

        if (!entry->used) {
            entry->used = 1;
            entry->visible = 0;
            entry->width = width;
            entry->height = height;
            entry->title = title == NULL ? emerald_string_from_cstr("Emerald") : title;
            entry->html = emerald_string_from_cstr("");
            entry->last_action[0] = 0;
            entry->preview_path[0] = 0;
            entry->browser_opened = 0;
            entry->native_window = NULL;
            entry->native_view = NULL;

#if defined(_WIN32)
            entry->server_socket = INVALID_SOCKET;
            entry->server_thread = NULL;
            entry->server_thread_id = 0;
            entry->server_port = 0;
            entry->server_running = 0;
            entry->webview2_environment = NULL;
            entry->webview2_controller = NULL;
            entry->webview2_webview = NULL;
            entry->webview2_environment_handler = NULL;
            entry->webview2_controller_handler = NULL;
            entry->webview2_navigation_handler = NULL;
            entry->webview2_navigation_token.value = 0;
            entry->webview2_requested = 0;
            entry->webview2_ready = 0;
            entry->webview2_failed = 0;
            emerald_ui_win32_create_window(entry);
#endif

#if !defined(_WIN32)
            if (emerald_ui_backend_ready) {
                entry->native_window = emerald_gtk_window_new(0);
                entry->native_view = emerald_webkit_web_view_new();

                if (entry->native_window != NULL && entry->native_view != NULL) {
                    emerald_gtk_window_set_title(entry->native_window, emerald_runtime_cstr(entry->title));
                    emerald_gtk_window_set_default_size(entry->native_window, width, height);
                    emerald_gtk_container_add(entry->native_window, entry->native_view);

                    if (emerald_g_signal_connect_data != NULL) {
                        emerald_g_signal_connect_data(entry->native_window, "destroy", (void *) emerald_ui_gtk_destroy_callback, entry, NULL, 0);
                        emerald_g_signal_connect_data(entry->native_view, "decide-policy", (void *) emerald_ui_webkit_decide_policy_callback, entry, NULL, 0);
                    }
                }
            }
#endif

            return index + 1;
        }

        index++;
    }

    return -1;
}

static void emerald_ui_write_dump_file(EmeraldUiWindow *entry) {
    const char *path = getenv("EMERALD_UI_DUMP_HTML");

    if (path == NULL || path[0] == 0 || entry == NULL || entry->html == NULL) {
        return;
    }

    FILE *file = fopen(path, "wb");

    if (file == NULL) {
        return;
    }

    fwrite(entry->html->bytes, 1, (size_t) entry->html->length, file);
    fclose(file);
}

int32_t emerald_ui_init(void) {
    emerald_ui_initialized = 1;

#if defined(_WIN32)
    emerald_ui_backend_ready = emerald_ui_load_windows_backend();
#else
    emerald_ui_backend_ready = emerald_ui_load_linux_webkitgtk();
#endif

    return 1;
}

EmeraldString *emerald_ui_backend(void) {
    if (!emerald_ui_initialized) {
        emerald_ui_init();
    }

    return emerald_string_from_cstr(emerald_ui_backend_name);
}

int32_t emerald_ui_create_window(EmeraldString *title, int32_t width, int32_t height) {
    if (!emerald_ui_initialized) {
        emerald_ui_init();
    }

    if (width <= 0) {
        width = 900;
    }

    if (height <= 0) {
        height = 600;
    }

    return emerald_ui_store_window(title, width, height);
}

int32_t emerald_ui_set_html(int32_t handle, EmeraldString *html) {
    EmeraldUiWindow *entry = emerald_ui_window_entry(handle);

    if (entry == NULL) {
        return 0;
    }

    entry->html = html == NULL ? emerald_string_from_cstr("") : html;

#if defined(_WIN32)
    if (emerald_ui_backend_ready && entry->webview2_ready) {
        emerald_ui_webview2_navigate_html(entry);
    }

    if (emerald_ui_backend_ready && !emerald_ui_webview2_available && entry->native_view != NULL) {
        emerald_ui_win32_update_preview_text(entry);
    }
#endif

#if !defined(_WIN32)
    if (emerald_ui_backend_ready && entry->native_view != NULL && emerald_webkit_web_view_load_html != NULL) {
        emerald_webkit_web_view_load_html(entry->native_view, emerald_runtime_cstr(entry->html), NULL);
    }
#endif

    return 1;
}

int32_t emerald_ui_set_title(int32_t handle, EmeraldString *title) {
    EmeraldUiWindow *entry = emerald_ui_window_entry(handle);

    if (entry == NULL) {
        return 0;
    }

    entry->title = title == NULL ? emerald_string_from_cstr("Emerald") : title;

#if defined(_WIN32)
    if (emerald_ui_backend_ready && entry->native_window != NULL) {
        SetWindowTextA((HWND) entry->native_window, emerald_runtime_cstr(entry->title));
    }
#endif

#if !defined(_WIN32)
    if (emerald_ui_backend_ready && entry->native_window != NULL && emerald_gtk_window_set_title != NULL) {
        emerald_gtk_window_set_title(entry->native_window, emerald_runtime_cstr(entry->title));
    }
#endif

    return 1;
}

int32_t emerald_ui_is_open(int32_t handle) {
    EmeraldUiWindow *entry = emerald_ui_window_entry(handle);

    if (entry == NULL) {
        return 0;
    }

    return entry->visible ? 1 : 0;
}

EmeraldString *emerald_ui_poll_action(int32_t handle) {
    EmeraldUiWindow *entry = emerald_ui_window_entry(handle);

    if (entry == NULL || entry->last_action[0] == 0) {
        return emerald_string_from_cstr("");
    }

    EmeraldString *action = emerald_string_from_cstr(entry->last_action);
    entry->last_action[0] = 0;
    return action;
}

int32_t emerald_ui_show(int32_t handle) {
    EmeraldUiWindow *entry = emerald_ui_window_entry(handle);

    if (entry == NULL) {
        return 0;
    }

    entry->visible = 1;
    emerald_ui_write_dump_file(entry);

#if defined(_WIN32)
    if (emerald_ui_backend_ready && entry->native_window != NULL) {
        ShowWindow((HWND) entry->native_window, SW_SHOW);
        UpdateWindow((HWND) entry->native_window);

        if (emerald_ui_webview2_available) {
            emerald_ui_webview2_start(entry);
            return 1;
        }

        if (!entry->browser_opened) {
            emerald_ui_win32_write_preview_file(entry);
            entry->browser_opened = emerald_ui_win32_open_edge_app(entry);
        }

        emerald_ui_win32_update_preview_text(entry);
        return 1;
    }
#endif

#if !defined(_WIN32)
    if (emerald_ui_backend_ready && entry->native_window != NULL && emerald_gtk_widget_show_all != NULL) {
        emerald_gtk_widget_show_all(entry->native_window);
        return 1;
    }
#endif

    fprintf(stdout, "[Emerald UI] %s (%dx%d)\n", emerald_runtime_cstr(entry->title), entry->width, entry->height);
    fflush(stdout);
    return 1;
}

int32_t emerald_ui_close(int32_t handle) {
    EmeraldUiWindow *entry = emerald_ui_window_entry(handle);

    if (entry == NULL) {
        return 0;
    }

#if defined(_WIN32)
    emerald_ui_win32_stop_http_server(entry);
    emerald_ui_webview2_release(entry);

    if (emerald_ui_backend_ready && entry->native_window != NULL) {
        DestroyWindow((HWND) entry->native_window);
    }
#endif

#if !defined(_WIN32)
    if (emerald_ui_backend_ready && entry->native_window != NULL && emerald_gtk_widget_destroy != NULL) {
        emerald_gtk_widget_destroy(entry->native_window);
    }
#endif

    entry->used = 0;
    entry->visible = 0;
    entry->title = NULL;
    entry->html = NULL;
    entry->preview_path[0] = 0;
    entry->browser_opened = 0;
    entry->native_window = NULL;
    entry->native_view = NULL;
#if defined(_WIN32)
    entry->server_socket = INVALID_SOCKET;
    entry->server_thread = NULL;
    entry->server_thread_id = 0;
    entry->server_port = 0;
    entry->server_running = 0;
    entry->webview2_environment = NULL;
    entry->webview2_controller = NULL;
    entry->webview2_webview = NULL;
    entry->webview2_environment_handler = NULL;
    entry->webview2_controller_handler = NULL;
    entry->webview2_navigation_handler = NULL;
    entry->webview2_navigation_token.value = 0;
    entry->webview2_requested = 0;
    entry->webview2_ready = 0;
    entry->webview2_failed = 0;
#endif
    return 1;
}

int32_t emerald_ui_pump(void) {
    if (!emerald_ui_initialized) {
        return 0;
    }

#if defined(_WIN32)
    if (emerald_ui_backend_ready) {
        MSG message;

        while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageA(&message);
        }
    }
#endif

#if !defined(_WIN32)
    if (emerald_ui_backend_ready && emerald_gtk_events_pending != NULL && emerald_gtk_main_iteration_do != NULL) {
        while (emerald_gtk_events_pending()) {
            emerald_gtk_main_iteration_do(0);
        }
    }
#endif

    return 1;
}

int32_t emerald_ui_run(void) {
    if (!emerald_ui_initialized) {
        return 0;
    }

#if defined(_WIN32)
    if (emerald_ui_backend_ready) {
        MSG message;

        while (emerald_ui_any_visible_window()) {
            if (emerald_ui_any_pending_action()) {
                return 1;
            }

            if (GetMessageA(&message, NULL, 0, 0) <= 0) {
                return 1;
            }

            TranslateMessage(&message);
            DispatchMessageA(&message);
        }

        return 1;
    }
#endif

#if !defined(_WIN32)
    if (emerald_ui_backend_ready && emerald_gtk_main != NULL) {
        emerald_gtk_main();
        return 1;
    }
#endif

    return 0;
}
