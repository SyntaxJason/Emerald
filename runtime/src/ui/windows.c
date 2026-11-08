#if defined(_WIN32)
static HINSTANCE emerald_ui_win32_instance = NULL;
static const char *emerald_ui_win32_class_name = "EmeraldNativeUiWindow";
static int emerald_ui_win32_registered = 0;
static HMODULE emerald_ui_webview2_loader = NULL;
static int emerald_ui_webview2_available = 0;

typedef struct ICoreWebView2Environment ICoreWebView2Environment;
typedef struct ICoreWebView2Controller ICoreWebView2Controller;
typedef struct ICoreWebView2 ICoreWebView2;
typedef struct ICoreWebView2NavigationStartingEventArgs ICoreWebView2NavigationStartingEventArgs;
typedef struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
typedef struct ICoreWebView2CreateCoreWebView2ControllerCompletedHandler ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
typedef struct ICoreWebView2NavigationStartingEventHandler ICoreWebView2NavigationStartingEventHandler;

typedef struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self, REFIID iid, void **value);
    ULONG (STDMETHODCALLTYPE *AddRef)(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self);
    ULONG (STDMETHODCALLTYPE *Release)(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self);
    HRESULT (STDMETHODCALLTYPE *Invoke)(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self, HRESULT result, ICoreWebView2Environment *environment);
} ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl;

struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler {
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl *lpVtbl;
};

typedef struct ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self, REFIID iid, void **value);
    ULONG (STDMETHODCALLTYPE *AddRef)(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self);
    ULONG (STDMETHODCALLTYPE *Release)(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self);
    HRESULT (STDMETHODCALLTYPE *Invoke)(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self, HRESULT result, ICoreWebView2Controller *controller);
} ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl;

struct ICoreWebView2CreateCoreWebView2ControllerCompletedHandler {
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl *lpVtbl;
};

typedef struct ICoreWebView2NavigationStartingEventHandlerVtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(ICoreWebView2NavigationStartingEventHandler *self, REFIID iid, void **value);
    ULONG (STDMETHODCALLTYPE *AddRef)(ICoreWebView2NavigationStartingEventHandler *self);
    ULONG (STDMETHODCALLTYPE *Release)(ICoreWebView2NavigationStartingEventHandler *self);
    HRESULT (STDMETHODCALLTYPE *Invoke)(ICoreWebView2NavigationStartingEventHandler *self, ICoreWebView2 *sender, ICoreWebView2NavigationStartingEventArgs *args);
} ICoreWebView2NavigationStartingEventHandlerVtbl;

struct ICoreWebView2NavigationStartingEventHandler {
    ICoreWebView2NavigationStartingEventHandlerVtbl *lpVtbl;
};

typedef struct ICoreWebView2EnvironmentVtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(ICoreWebView2Environment *self, REFIID iid, void **value);
    ULONG (STDMETHODCALLTYPE *AddRef)(ICoreWebView2Environment *self);
    ULONG (STDMETHODCALLTYPE *Release)(ICoreWebView2Environment *self);
    HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2Controller)(ICoreWebView2Environment *self, HWND parent_window, ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *handler);
    HRESULT (STDMETHODCALLTYPE *CreateWebResourceResponse)(ICoreWebView2Environment *self, void *content, int status_code, LPCWSTR reason_phrase, LPCWSTR headers, void **response);
    HRESULT (STDMETHODCALLTYPE *get_BrowserVersionString)(ICoreWebView2Environment *self, LPWSTR *version_info);
    HRESULT (STDMETHODCALLTYPE *add_NewBrowserVersionAvailable)(ICoreWebView2Environment *self, void *event_handler, EventRegistrationToken *token);
    HRESULT (STDMETHODCALLTYPE *remove_NewBrowserVersionAvailable)(ICoreWebView2Environment *self, EventRegistrationToken token);
} ICoreWebView2EnvironmentVtbl;

struct ICoreWebView2Environment {
    ICoreWebView2EnvironmentVtbl *lpVtbl;
};

typedef struct ICoreWebView2ControllerVtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(ICoreWebView2Controller *self, REFIID iid, void **value);
    ULONG (STDMETHODCALLTYPE *AddRef)(ICoreWebView2Controller *self);
    ULONG (STDMETHODCALLTYPE *Release)(ICoreWebView2Controller *self);
    HRESULT (STDMETHODCALLTYPE *get_IsVisible)(ICoreWebView2Controller *self, BOOL *visible);
    HRESULT (STDMETHODCALLTYPE *put_IsVisible)(ICoreWebView2Controller *self, BOOL visible);
    HRESULT (STDMETHODCALLTYPE *get_Bounds)(ICoreWebView2Controller *self, RECT *bounds);
    HRESULT (STDMETHODCALLTYPE *put_Bounds)(ICoreWebView2Controller *self, RECT bounds);
    HRESULT (STDMETHODCALLTYPE *get_ZoomFactor)(ICoreWebView2Controller *self, double *zoom_factor);
    HRESULT (STDMETHODCALLTYPE *put_ZoomFactor)(ICoreWebView2Controller *self, double zoom_factor);
    HRESULT (STDMETHODCALLTYPE *add_ZoomFactorChanged)(ICoreWebView2Controller *self, void *event_handler, EventRegistrationToken *token);
    HRESULT (STDMETHODCALLTYPE *remove_ZoomFactorChanged)(ICoreWebView2Controller *self, EventRegistrationToken token);
    HRESULT (STDMETHODCALLTYPE *SetBoundsAndZoomFactor)(ICoreWebView2Controller *self, RECT bounds, double zoom_factor);
    HRESULT (STDMETHODCALLTYPE *MoveFocus)(ICoreWebView2Controller *self, int reason);
    HRESULT (STDMETHODCALLTYPE *add_MoveFocusRequested)(ICoreWebView2Controller *self, void *event_handler, EventRegistrationToken *token);
    HRESULT (STDMETHODCALLTYPE *remove_MoveFocusRequested)(ICoreWebView2Controller *self, EventRegistrationToken token);
    HRESULT (STDMETHODCALLTYPE *add_GotFocus)(ICoreWebView2Controller *self, void *event_handler, EventRegistrationToken *token);
    HRESULT (STDMETHODCALLTYPE *remove_GotFocus)(ICoreWebView2Controller *self, EventRegistrationToken token);
    HRESULT (STDMETHODCALLTYPE *add_LostFocus)(ICoreWebView2Controller *self, void *event_handler, EventRegistrationToken *token);
    HRESULT (STDMETHODCALLTYPE *remove_LostFocus)(ICoreWebView2Controller *self, EventRegistrationToken token);
    HRESULT (STDMETHODCALLTYPE *add_AcceleratorKeyPressed)(ICoreWebView2Controller *self, void *event_handler, EventRegistrationToken *token);
    HRESULT (STDMETHODCALLTYPE *remove_AcceleratorKeyPressed)(ICoreWebView2Controller *self, EventRegistrationToken token);
    HRESULT (STDMETHODCALLTYPE *get_ParentWindow)(ICoreWebView2Controller *self, HWND *parent_window);
    HRESULT (STDMETHODCALLTYPE *put_ParentWindow)(ICoreWebView2Controller *self, HWND parent_window);
    HRESULT (STDMETHODCALLTYPE *NotifyParentWindowPositionChanged)(ICoreWebView2Controller *self);
    HRESULT (STDMETHODCALLTYPE *Close)(ICoreWebView2Controller *self);
    HRESULT (STDMETHODCALLTYPE *get_CoreWebView2)(ICoreWebView2Controller *self, ICoreWebView2 **webview);
} ICoreWebView2ControllerVtbl;

struct ICoreWebView2Controller {
    ICoreWebView2ControllerVtbl *lpVtbl;
};

typedef struct ICoreWebView2Vtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(ICoreWebView2 *self, REFIID iid, void **value);
    ULONG (STDMETHODCALLTYPE *AddRef)(ICoreWebView2 *self);
    ULONG (STDMETHODCALLTYPE *Release)(ICoreWebView2 *self);
    HRESULT (STDMETHODCALLTYPE *get_Settings)(ICoreWebView2 *self, void **settings);
    HRESULT (STDMETHODCALLTYPE *get_Source)(ICoreWebView2 *self, LPWSTR *uri);
    HRESULT (STDMETHODCALLTYPE *Navigate)(ICoreWebView2 *self, LPCWSTR uri);
    HRESULT (STDMETHODCALLTYPE *NavigateToString)(ICoreWebView2 *self, LPCWSTR html_content);
    HRESULT (STDMETHODCALLTYPE *add_NavigationStarting)(ICoreWebView2 *self, ICoreWebView2NavigationStartingEventHandler *handler, EventRegistrationToken *token);
    HRESULT (STDMETHODCALLTYPE *remove_NavigationStarting)(ICoreWebView2 *self, EventRegistrationToken token);
} ICoreWebView2Vtbl;

struct ICoreWebView2 {
    ICoreWebView2Vtbl *lpVtbl;
};

typedef struct ICoreWebView2NavigationStartingEventArgsVtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(ICoreWebView2NavigationStartingEventArgs *self, REFIID iid, void **value);
    ULONG (STDMETHODCALLTYPE *AddRef)(ICoreWebView2NavigationStartingEventArgs *self);
    ULONG (STDMETHODCALLTYPE *Release)(ICoreWebView2NavigationStartingEventArgs *self);
    HRESULT (STDMETHODCALLTYPE *get_uri)(ICoreWebView2NavigationStartingEventArgs *self, LPWSTR *uri);
    HRESULT (STDMETHODCALLTYPE *get_IsUserInitiated)(ICoreWebView2NavigationStartingEventArgs *self, BOOL *value);
    HRESULT (STDMETHODCALLTYPE *get_IsRedirected)(ICoreWebView2NavigationStartingEventArgs *self, BOOL *value);
    HRESULT (STDMETHODCALLTYPE *get_RequestHeaders)(ICoreWebView2NavigationStartingEventArgs *self, void **headers);
    HRESULT (STDMETHODCALLTYPE *get_Cancel)(ICoreWebView2NavigationStartingEventArgs *self, BOOL *cancel);
    HRESULT (STDMETHODCALLTYPE *put_Cancel)(ICoreWebView2NavigationStartingEventArgs *self, BOOL cancel);
    HRESULT (STDMETHODCALLTYPE *get_NavigationId)(ICoreWebView2NavigationStartingEventArgs *self, uint64_t *navigation_id);
} ICoreWebView2NavigationStartingEventArgsVtbl;

struct ICoreWebView2NavigationStartingEventArgs {
    ICoreWebView2NavigationStartingEventArgsVtbl *lpVtbl;
};

typedef HRESULT (WINAPI *EmeraldCreateCoreWebView2EnvironmentWithOptionsFn)(LPCWSTR browser_executable_folder, LPCWSTR user_data_folder, void *environment_options, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *handler);

static EmeraldCreateCoreWebView2EnvironmentWithOptionsFn emerald_create_webview2_environment = NULL;

static int emerald_ui_any_visible_window(void) {
    int index = 0;

    while (index < EMERALD_UI_MAX_WINDOWS) {
        if (emerald_ui_windows[index].used && emerald_ui_windows[index].visible) {
            return 1;
        }

        index++;
    }

    return 0;
}

static int emerald_ui_any_pending_action(void) {
    int index = 0;

    while (index < EMERALD_UI_MAX_WINDOWS) {
        if (emerald_ui_windows[index].used && emerald_ui_windows[index].last_action[0] != 0) {
            return 1;
        }

        index++;
    }

    return 0;
}

#define EMERALD_UI_WIN32_WAKE_MESSAGE (WM_APP + 41)

static int emerald_ui_win32_hex_value(char value) {
    if (value >= '0' && value <= '9') {
        return value - '0';
    }

    if (value >= 'a' && value <= 'f') {
        return value - 'a' + 10;
    }

    if (value >= 'A' && value <= 'F') {
        return value - 'A' + 10;
    }

    return -1;
}

static void emerald_ui_win32_decode_component(const char *source, char *target, size_t target_size) {
    if (target_size == 0) {
        return;
    }

    size_t source_index = 0;
    size_t target_index = 0;

    while (source != NULL && source[source_index] != 0 && target_index + 1 < target_size) {
        char current = source[source_index];

        if (current == '%' && source[source_index + 1] != 0 && source[source_index + 2] != 0) {
            int high = emerald_ui_win32_hex_value(source[source_index + 1]);
            int low = emerald_ui_win32_hex_value(source[source_index + 2]);

            if (high >= 0 && low >= 0) {
                target[target_index++] = (char) ((high << 4) | low);
                source_index += 3;
                continue;
            }
        }

        if (current == '+') {
            target[target_index++] = ' ';
            source_index++;
            continue;
        }

        target[target_index++] = current;
        source_index++;
    }

    target[target_index] = 0;
}

static wchar_t *emerald_ui_win32_wide_from_utf8(const char *value) {
    if (value == NULL) {
        value = "";
    }

    int length = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);

    if (length <= 0) {
        return NULL;
    }

    wchar_t *wide = (wchar_t *) calloc((size_t) length, sizeof(wchar_t));

    if (wide == NULL) {
        return NULL;
    }

    MultiByteToWideChar(CP_UTF8, 0, value, -1, wide, length);
    return wide;
}

static char *emerald_ui_win32_utf8_from_wide(const wchar_t *value) {
    if (value == NULL) {
        return NULL;
    }

    int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);

    if (length <= 0) {
        return NULL;
    }

    char *text = (char *) calloc((size_t) length, sizeof(char));

    if (text == NULL) {
        return NULL;
    }

    WideCharToMultiByte(CP_UTF8, 0, value, -1, text, length, NULL, NULL);
    return text;
}

static wchar_t *emerald_ui_win32_user_data_folder(void) {
    char directory[MAX_PATH];
    DWORD length = GetTempPathA((DWORD) sizeof(directory), directory);

    if (length == 0 || length >= sizeof(directory)) {
        snprintf(directory, sizeof(directory), ".\\");
    }

    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%sEmeraldWebView2", directory);
    CreateDirectoryA(path, NULL);
    return emerald_ui_win32_wide_from_utf8(path);
}

static void emerald_ui_win32_store_action(EmeraldUiWindow *entry, const char *encoded) {
    if (entry == NULL || encoded == NULL) {
        return;
    }

    emerald_ui_win32_decode_component(encoded, entry->last_action, sizeof(entry->last_action));

    if (entry->native_window != NULL) {
        PostMessageA((HWND) entry->native_window, EMERALD_UI_WIN32_WAKE_MESSAGE, 0, 0);
    }
}

static HRESULT emerald_ui_webview2_handler_query(void *self, REFIID iid, void **value) {
    (void) iid;

    if (value == NULL) {
        return E_POINTER;
    }

    *value = self;
    ((IUnknown *) self)->lpVtbl->AddRef((IUnknown *) self);
    return S_OK;
}

typedef struct EmeraldWebView2EnvironmentHandler {
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler iface;
    LONG refs;
    EmeraldUiWindow *entry;
} EmeraldWebView2EnvironmentHandler;

typedef struct EmeraldWebView2ControllerHandler {
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler iface;
    LONG refs;
    EmeraldUiWindow *entry;
} EmeraldWebView2ControllerHandler;

typedef struct EmeraldWebView2NavigationHandler {
    ICoreWebView2NavigationStartingEventHandler iface;
    LONG refs;
    EmeraldUiWindow *entry;
} EmeraldWebView2NavigationHandler;

static ULONG STDMETHODCALLTYPE emerald_ui_webview2_environment_add_ref(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self) {
    EmeraldWebView2EnvironmentHandler *handler = (EmeraldWebView2EnvironmentHandler *) self;
    return (ULONG) InterlockedIncrement(&handler->refs);
}

static ULONG STDMETHODCALLTYPE emerald_ui_webview2_environment_release(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self) {
    EmeraldWebView2EnvironmentHandler *handler = (EmeraldWebView2EnvironmentHandler *) self;
    LONG refs = InterlockedDecrement(&handler->refs);

    if (refs == 0) {
        free(handler);
    }

    return (ULONG) refs;
}

static ULONG STDMETHODCALLTYPE emerald_ui_webview2_controller_add_ref(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self) {
    EmeraldWebView2ControllerHandler *handler = (EmeraldWebView2ControllerHandler *) self;
    return (ULONG) InterlockedIncrement(&handler->refs);
}

static ULONG STDMETHODCALLTYPE emerald_ui_webview2_controller_release(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self) {
    EmeraldWebView2ControllerHandler *handler = (EmeraldWebView2ControllerHandler *) self;
    LONG refs = InterlockedDecrement(&handler->refs);

    if (refs == 0) {
        free(handler);
    }

    return (ULONG) refs;
}

static ULONG STDMETHODCALLTYPE emerald_ui_webview2_navigation_add_ref(ICoreWebView2NavigationStartingEventHandler *self) {
    EmeraldWebView2NavigationHandler *handler = (EmeraldWebView2NavigationHandler *) self;
    return (ULONG) InterlockedIncrement(&handler->refs);
}

static ULONG STDMETHODCALLTYPE emerald_ui_webview2_navigation_release(ICoreWebView2NavigationStartingEventHandler *self) {
    EmeraldWebView2NavigationHandler *handler = (EmeraldWebView2NavigationHandler *) self;
    LONG refs = InterlockedDecrement(&handler->refs);

    if (refs == 0) {
        free(handler);
    }

    return (ULONG) refs;
}

static HRESULT STDMETHODCALLTYPE emerald_ui_webview2_environment_query(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self, REFIID iid, void **value) {
    return emerald_ui_webview2_handler_query(self, iid, value);
}

static HRESULT STDMETHODCALLTYPE emerald_ui_webview2_controller_query(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self, REFIID iid, void **value) {
    return emerald_ui_webview2_handler_query(self, iid, value);
}

static HRESULT STDMETHODCALLTYPE emerald_ui_webview2_navigation_query(ICoreWebView2NavigationStartingEventHandler *self, REFIID iid, void **value) {
    return emerald_ui_webview2_handler_query(self, iid, value);
}

static void emerald_ui_webview2_resize(EmeraldUiWindow *entry) {
    if (entry == NULL || entry->native_window == NULL || entry->webview2_controller == NULL) {
        return;
    }

    RECT bounds;
    GetClientRect((HWND) entry->native_window, &bounds);
    ((ICoreWebView2Controller *) entry->webview2_controller)->lpVtbl->put_Bounds((ICoreWebView2Controller *) entry->webview2_controller, bounds);
}

static void emerald_ui_webview2_navigate_html(EmeraldUiWindow *entry) {
    if (entry == NULL || entry->webview2_webview == NULL || entry->html == NULL) {
        return;
    }

    wchar_t *html = emerald_ui_win32_wide_from_utf8(emerald_runtime_cstr(entry->html));

    if (html == NULL) {
        return;
    }

    ((ICoreWebView2 *) entry->webview2_webview)->lpVtbl->NavigateToString((ICoreWebView2 *) entry->webview2_webview, html);
    free(html);
}

static HRESULT STDMETHODCALLTYPE emerald_ui_webview2_navigation_invoke(ICoreWebView2NavigationStartingEventHandler *self, ICoreWebView2 *sender, ICoreWebView2NavigationStartingEventArgs *args) {
    (void) sender;

    EmeraldWebView2NavigationHandler *handler = (EmeraldWebView2NavigationHandler *) self;

    if (handler == NULL || handler->entry == NULL || args == NULL) {
        return S_OK;
    }

    LPWSTR wide_uri = NULL;
    HRESULT result = args->lpVtbl->get_uri(args, &wide_uri);

    if (FAILED(result) || wide_uri == NULL) {
        return S_OK;
    }

    char *uri = emerald_ui_win32_utf8_from_wide(wide_uri);
    CoTaskMemFree(wide_uri);

    if (uri == NULL) {
        return S_OK;
    }

    if (strncmp(uri, "emerald://action/", 17) == 0) {
        emerald_ui_win32_store_action(handler->entry, uri + 17);
        args->lpVtbl->put_Cancel(args, TRUE);
    }

    free(uri);
    return S_OK;
}

static ICoreWebView2NavigationStartingEventHandlerVtbl emerald_ui_webview2_navigation_vtbl = {
    emerald_ui_webview2_navigation_query,
    emerald_ui_webview2_navigation_add_ref,
    emerald_ui_webview2_navigation_release,
    emerald_ui_webview2_navigation_invoke
};

static HRESULT STDMETHODCALLTYPE emerald_ui_webview2_controller_invoke(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *self, HRESULT result, ICoreWebView2Controller *controller) {
    EmeraldWebView2ControllerHandler *handler = (EmeraldWebView2ControllerHandler *) self;
    EmeraldUiWindow *entry = handler == NULL ? NULL : handler->entry;

    if (entry == NULL || FAILED(result) || controller == NULL) {
        if (entry != NULL) {
            entry->webview2_failed = 1;
        }

        return S_OK;
    }

    entry->webview2_controller = controller;
    controller->lpVtbl->AddRef(controller);
    controller->lpVtbl->put_IsVisible(controller, TRUE);
    emerald_ui_webview2_resize(entry);

    ICoreWebView2 *webview = NULL;

    if (SUCCEEDED(controller->lpVtbl->get_CoreWebView2(controller, &webview)) && webview != NULL) {
        entry->webview2_webview = webview;
        webview->lpVtbl->AddRef(webview);

        EmeraldWebView2NavigationHandler *navigation = (EmeraldWebView2NavigationHandler *) calloc(1, sizeof(EmeraldWebView2NavigationHandler));

        if (navigation != NULL) {
            navigation->iface.lpVtbl = &emerald_ui_webview2_navigation_vtbl;
            navigation->refs = 1;
            navigation->entry = entry;
            entry->webview2_navigation_handler = navigation;
            webview->lpVtbl->add_NavigationStarting(webview, (ICoreWebView2NavigationStartingEventHandler *) navigation, &entry->webview2_navigation_token);
        }

        entry->webview2_ready = 1;
        emerald_ui_webview2_navigate_html(entry);
    }

    return S_OK;
}

static ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl emerald_ui_webview2_controller_vtbl = {
    emerald_ui_webview2_controller_query,
    emerald_ui_webview2_controller_add_ref,
    emerald_ui_webview2_controller_release,
    emerald_ui_webview2_controller_invoke
};

static HRESULT STDMETHODCALLTYPE emerald_ui_webview2_environment_invoke(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *self, HRESULT result, ICoreWebView2Environment *environment) {
    EmeraldWebView2EnvironmentHandler *handler = (EmeraldWebView2EnvironmentHandler *) self;
    EmeraldUiWindow *entry = handler == NULL ? NULL : handler->entry;

    if (entry == NULL || FAILED(result) || environment == NULL || entry->native_window == NULL) {
        if (entry != NULL) {
            entry->webview2_failed = 1;
        }

        return S_OK;
    }

    entry->webview2_environment = environment;
    environment->lpVtbl->AddRef(environment);

    EmeraldWebView2ControllerHandler *controller_handler = (EmeraldWebView2ControllerHandler *) calloc(1, sizeof(EmeraldWebView2ControllerHandler));

    if (controller_handler == NULL) {
        entry->webview2_failed = 1;
        return S_OK;
    }

    controller_handler->iface.lpVtbl = &emerald_ui_webview2_controller_vtbl;
    controller_handler->refs = 1;
    controller_handler->entry = entry;
    entry->webview2_controller_handler = controller_handler;

    HRESULT controller_result = environment->lpVtbl->CreateCoreWebView2Controller(environment, (HWND) entry->native_window, (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *) controller_handler);

    if (FAILED(controller_result)) {
        entry->webview2_failed = 1;
    }

    return S_OK;
}

static ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl emerald_ui_webview2_environment_vtbl = {
    emerald_ui_webview2_environment_query,
    emerald_ui_webview2_environment_add_ref,
    emerald_ui_webview2_environment_release,
    emerald_ui_webview2_environment_invoke
};

static int emerald_ui_webview2_start(EmeraldUiWindow *entry) {
    if (entry == NULL || entry->native_window == NULL || !emerald_ui_webview2_available || emerald_create_webview2_environment == NULL) {
        return 0;
    }

    if (entry->webview2_requested || entry->webview2_ready) {
        return 1;
    }

    HRESULT init_result = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

    if (FAILED(init_result) && init_result != RPC_E_CHANGED_MODE) {
        entry->webview2_failed = 1;
        return 0;
    }

    EmeraldWebView2EnvironmentHandler *handler = (EmeraldWebView2EnvironmentHandler *) calloc(1, sizeof(EmeraldWebView2EnvironmentHandler));

    if (handler == NULL) {
        entry->webview2_failed = 1;
        return 0;
    }

    handler->iface.lpVtbl = &emerald_ui_webview2_environment_vtbl;
    handler->refs = 1;
    handler->entry = entry;
    entry->webview2_environment_handler = handler;
    entry->webview2_requested = 1;

    wchar_t *user_data_folder = emerald_ui_win32_user_data_folder();
    HRESULT result = emerald_create_webview2_environment(NULL, user_data_folder, NULL, (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *) handler);

    if (user_data_folder != NULL) {
        free(user_data_folder);
    }

    if (FAILED(result)) {
        entry->webview2_failed = 1;
        return 0;
    }

    return 1;
}

static void emerald_ui_webview2_release(EmeraldUiWindow *entry) {
    if (entry == NULL) {
        return;
    }

    if (entry->webview2_controller != NULL) {
        ((ICoreWebView2Controller *) entry->webview2_controller)->lpVtbl->Close((ICoreWebView2Controller *) entry->webview2_controller);
        ((ICoreWebView2Controller *) entry->webview2_controller)->lpVtbl->Release((ICoreWebView2Controller *) entry->webview2_controller);
        entry->webview2_controller = NULL;
    }

    if (entry->webview2_webview != NULL) {
        ((ICoreWebView2 *) entry->webview2_webview)->lpVtbl->Release((ICoreWebView2 *) entry->webview2_webview);
        entry->webview2_webview = NULL;
    }

    if (entry->webview2_environment != NULL) {
        ((ICoreWebView2Environment *) entry->webview2_environment)->lpVtbl->Release((ICoreWebView2Environment *) entry->webview2_environment);
        entry->webview2_environment = NULL;
    }

    entry->webview2_environment_handler = NULL;
    entry->webview2_controller_handler = NULL;
    entry->webview2_navigation_handler = NULL;
    entry->webview2_requested = 0;
    entry->webview2_ready = 0;
}

static void emerald_ui_win32_send_all(SOCKET socket_value, const char *buffer, int length) {
    int offset = 0;

    while (offset < length) {
        int sent = send(socket_value, buffer + offset, length - offset, 0);

        if (sent <= 0) {
            return;
        }

        offset += sent;
    }
}

static void emerald_ui_win32_send_response(SOCKET socket_value, const char *status, const char *content_type, const char *body, size_t body_length) {
    char header[512];
    int header_length = snprintf(
        header,
        sizeof(header),
        "HTTP/1.1 %s\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %llu\r\n"
        "Cache-Control: no-store\r\n"
        "Connection: close\r\n"
        "\r\n",
        status,
        content_type,
        (unsigned long long) body_length
    );

    emerald_ui_win32_send_all(socket_value, header, header_length);

    if (body != NULL && body_length > 0) {
        emerald_ui_win32_send_all(socket_value, body, (int) body_length);
    }
}

static DWORD WINAPI emerald_ui_win32_http_thread(void *data) {
    EmeraldUiWindow *entry = (EmeraldUiWindow *) data;

    while (entry != NULL && entry->server_running) {
        SOCKET client = accept(entry->server_socket, NULL, NULL);

        if (client == INVALID_SOCKET) {
            continue;
        }

        char request[8192];
        int length = recv(client, request, (int) sizeof(request) - 1, 0);

        if (length <= 0) {
            closesocket(client);
            continue;
        }

        request[length] = 0;

        char method[16];
        char path[2048];
        method[0] = 0;
        path[0] = 0;
        sscanf(request, "%15s %2047s", method, path);

        const char *action_prefix = "/__emerald_action/";
        size_t action_prefix_length = strlen(action_prefix);

        if (strncmp(path, action_prefix, action_prefix_length) == 0) {
            emerald_ui_win32_store_action(entry, path + action_prefix_length);
            emerald_ui_win32_send_response(client, "204 No Content", "text/plain; charset=utf-8", "", 0);
            shutdown(client, SD_BOTH);
            closesocket(client);
            continue;
        }

        const char *html = entry->html == NULL ? "" : emerald_runtime_cstr(entry->html);
        size_t html_length = entry->html == NULL ? 0 : (size_t) entry->html->length;
        emerald_ui_win32_send_response(client, "200 OK", "text/html; charset=utf-8", html, html_length);
        shutdown(client, SD_BOTH);
        closesocket(client);
    }

    return 0;
}

static int emerald_ui_win32_start_http_server(EmeraldUiWindow *entry) {
    if (entry == NULL) {
        return 0;
    }

    if (entry->server_running) {
        return 1;
    }

    if (!emerald_runtime_socket_ready()) {
        return 0;
    }

    SOCKET server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);

    if (server == INVALID_SOCKET) {
        return 0;
    }

    int option = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, (const char *) &option, sizeof(option));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(0);

    if (bind(server, (struct sockaddr *) &address, sizeof(address)) != 0) {
        closesocket(server);
        return 0;
    }

    if (listen(server, 16) != 0) {
        closesocket(server);
        return 0;
    }

    struct sockaddr_in bound;
    int bound_length = sizeof(bound);

    if (getsockname(server, (struct sockaddr *) &bound, &bound_length) != 0) {
        closesocket(server);
        return 0;
    }

    entry->server_socket = server;
    entry->server_port = ntohs(bound.sin_port);
    entry->server_running = 1;
    entry->server_thread = CreateThread(NULL, 0, emerald_ui_win32_http_thread, entry, 0, &entry->server_thread_id);

    if (entry->server_thread == NULL) {
        entry->server_running = 0;
        closesocket(server);
        entry->server_socket = INVALID_SOCKET;
        entry->server_port = 0;
        return 0;
    }

    return 1;
}

static void emerald_ui_win32_stop_http_server(EmeraldUiWindow *entry) {
    if (entry == NULL || !entry->server_running) {
        return;
    }

    entry->server_running = 0;

    if (entry->server_socket != INVALID_SOCKET) {
        closesocket(entry->server_socket);
        entry->server_socket = INVALID_SOCKET;
    }

    if (entry->server_thread != NULL) {
        WaitForSingleObject(entry->server_thread, 500);
        CloseHandle(entry->server_thread);
        entry->server_thread = NULL;
    }

    entry->server_port = 0;
}

static int emerald_ui_win32_open_edge_app(EmeraldUiWindow *entry) {
    if (entry == NULL) {
        return 0;
    }

    if (!emerald_ui_win32_start_http_server(entry)) {
        return 0;
    }

    char url[256];
    snprintf(url, sizeof(url), "http://127.0.0.1:%d/", entry->server_port);

    char args[512];
    snprintf(args, sizeof(args), "--app=%s", url);

    HINSTANCE result = ShellExecuteA(NULL, "open", "msedge.exe", args, NULL, SW_SHOWNORMAL);

    if ((INT_PTR) result > 32) {
        return 1;
    }

    result = ShellExecuteA(NULL, "open", url, NULL, NULL, SW_SHOWNORMAL);
    return (INT_PTR) result > 32 ? 1 : 0;
}

static int emerald_ui_win32_write_preview_file(EmeraldUiWindow *entry) {
    if (entry == NULL || entry->html == NULL) {
        return 0;
    }

    if (entry->preview_path[0] == 0) {
        char directory[MAX_PATH];
        DWORD length = GetTempPathA((DWORD) sizeof(directory), directory);

        if (length == 0 || length >= sizeof(directory)) {
            snprintf(entry->preview_path, sizeof(entry->preview_path), "%s", "emerald-ui-preview.html");
        } else {
            snprintf(entry->preview_path, sizeof(entry->preview_path), "%semerald-ui-%p.html", directory, (void *) entry);
        }
    }

    FILE *file = fopen(entry->preview_path, "wb");

    if (file == NULL) {
        return 0;
    }

    fwrite(entry->html->bytes, 1, (size_t) entry->html->length, file);
    fclose(file);
    return 1;
}

static void emerald_ui_win32_update_preview_text(EmeraldUiWindow *entry) {
    if (entry == NULL || entry->native_view == NULL) {
        return;
    }

    emerald_ui_win32_write_preview_file(entry);

    char text[8192];
    snprintf(
        text,
        sizeof(text),
        "Emerald Windows UI Fallback\r\n"
        "\r\n"
        "WebView2 is not active for this window.\r\n"
        "The fallback starts a local Emerald UI server and opens Edge/app browser mode.\r\n"
        "\r\n"
        "Local URL:\r\n"
        "http://127.0.0.1:%d/\r\n"
        "\r\n"
        "Debug HTML file:\r\n"
        "%s",
        entry->server_port,
        entry->preview_path[0] == 0 ? "<not written>" : entry->preview_path
    );

    SetWindowTextA((HWND) entry->native_view, text);
}

static LRESULT CALLBACK emerald_ui_win32_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    EmeraldUiWindow *entry = (EmeraldUiWindow *) GetWindowLongPtrA(window, GWLP_USERDATA);

    if (message == WM_NCCREATE) {
        CREATESTRUCTA *create = (CREATESTRUCTA *) lparam;
        SetWindowLongPtrA(window, GWLP_USERDATA, (LONG_PTR) create->lpCreateParams);
        return DefWindowProcA(window, message, wparam, lparam);
    }

    if (message == WM_SIZE) {
        if (entry != NULL && entry->webview2_controller != NULL) {
            emerald_ui_webview2_resize(entry);
            return 0;
        }

        if (entry != NULL && entry->native_view != NULL) {
            RECT rect;
            GetClientRect(window, &rect);
            MoveWindow((HWND) entry->native_view, 0, 0, rect.right - rect.left, rect.bottom - rect.top, TRUE);
        }

        return 0;
    }

    if (message == EMERALD_UI_WIN32_WAKE_MESSAGE) {
        return 0;
    }

    if (message == WM_DESTROY) {
        if (entry != NULL) {
            entry->visible = 0;
        }

        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcA(window, message, wparam, lparam);
}

static int emerald_ui_win32_register_class(void) {
    if (emerald_ui_win32_registered) {
        return 1;
    }

    emerald_ui_win32_instance = GetModuleHandleA(NULL);

    WNDCLASSEXA window_class;
    memset(&window_class, 0, sizeof(window_class));
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = emerald_ui_win32_window_proc;
    window_class.hInstance = emerald_ui_win32_instance;
    window_class.lpszClassName = emerald_ui_win32_class_name;
    window_class.hCursor = LoadCursorA(NULL, IDC_ARROW);
    window_class.hbrBackground = (HBRUSH) (COLOR_WINDOW + 1);

    if (!RegisterClassExA(&window_class)) {
        DWORD error = GetLastError();

        if (error != ERROR_CLASS_ALREADY_EXISTS) {
            return 0;
        }
    }

    emerald_ui_win32_registered = 1;
    return 1;
}

static int emerald_ui_load_windows_backend(void) {
    const char *forced = getenv("EMERALD_UI_BACKEND");

    if (forced != NULL && strcmp(forced, "headless") == 0) {
        snprintf(emerald_ui_backend_name, sizeof(emerald_ui_backend_name), "%s", "windows-headless");
        return 0;
    }

    const char *loader_path = getenv("EMERALD_WEBVIEW2_LOADER");

    if (loader_path != NULL && loader_path[0] != 0) {
        emerald_ui_webview2_loader = LoadLibraryA(loader_path);
    }

    if (emerald_ui_webview2_loader == NULL) {
        emerald_ui_webview2_loader = LoadLibraryA("WebView2Loader.dll");
    }

    if (emerald_ui_webview2_loader != NULL) {
        emerald_create_webview2_environment = (EmeraldCreateCoreWebView2EnvironmentWithOptionsFn) GetProcAddress(emerald_ui_webview2_loader, "CreateCoreWebView2EnvironmentWithOptions");

        if (emerald_create_webview2_environment != NULL) {
            emerald_ui_webview2_available = 1;
            snprintf(emerald_ui_backend_name, sizeof(emerald_ui_backend_name), "%s", "windows-webview2-dynamic");
            return emerald_ui_win32_register_class();
        }
    }

    snprintf(emerald_ui_backend_name, sizeof(emerald_ui_backend_name), "%s", "windows-edge-app-live-fallback");
    return emerald_ui_win32_register_class();
}

static void emerald_ui_win32_create_window(EmeraldUiWindow *entry) {
    if (entry == NULL || !emerald_ui_backend_ready) {
        return;
    }

    HWND window = CreateWindowExA(
        0,
        emerald_ui_win32_class_name,
        emerald_runtime_cstr(entry->title),
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        entry->width,
        entry->height,
        NULL,
        NULL,
        emerald_ui_win32_instance,
        entry
    );

    if (window == NULL) {
        return;
    }

    entry->native_window = window;

    if (emerald_ui_webview2_available) {
        return;
    }

    HWND view = CreateWindowExA(
        WS_EX_CLIENTEDGE,
        "EDIT",
        "",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_READONLY | WS_VSCROLL | WS_HSCROLL,
        0,
        0,
        entry->width,
        entry->height,
        window,
        NULL,
        emerald_ui_win32_instance,
        NULL
    );

    entry->native_view = view;
}
#endif
