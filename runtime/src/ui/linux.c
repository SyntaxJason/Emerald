#if !defined(_WIN32)
typedef void *(*EmeraldGtkWindowNewFn)(int type);
typedef void (*EmeraldGtkWindowSetTitleFn)(void *window, const char *title);
typedef void (*EmeraldGtkWindowSetDefaultSizeFn)(void *window, int width, int height);
typedef void (*EmeraldGtkContainerAddFn)(void *container, void *widget);
typedef void (*EmeraldGtkWidgetShowAllFn)(void *widget);
typedef void (*EmeraldGtkWidgetDestroyFn)(void *widget);
typedef int (*EmeraldGtkEventsPendingFn)(void);
typedef int (*EmeraldGtkMainIterationDoFn)(int blocking);
typedef void (*EmeraldGtkMainFn)(void);
typedef void (*EmeraldGtkMainQuitFn)(void);
typedef void (*EmeraldGtkInitFn)(int *argc, char ***argv);
typedef void *(*EmeraldWebKitWebViewNewFn)(void);
typedef void (*EmeraldWebKitWebViewLoadHtmlFn)(void *view, const char *html, const char *base_uri);
typedef void *(*EmeraldWebKitNavigationPolicyDecisionGetRequestFn)(void *decision);
typedef const char *(*EmeraldWebKitUriRequestGetUriFn)(void *request);
typedef void (*EmeraldWebKitPolicyDecisionIgnoreFn)(void *decision);
typedef unsigned long (*EmeraldGSignalConnectDataFn)(void *instance, const char *detailed_signal, void *callback, void *data, void *destroy_data, int flags);

static void *emerald_ui_gtk_library = NULL;
static void *emerald_ui_gobject_library = NULL;
static void *emerald_ui_webkit_library = NULL;

static EmeraldGtkWindowNewFn emerald_gtk_window_new = NULL;
static EmeraldGtkWindowSetTitleFn emerald_gtk_window_set_title = NULL;
static EmeraldGtkWindowSetDefaultSizeFn emerald_gtk_window_set_default_size = NULL;
static EmeraldGtkContainerAddFn emerald_gtk_container_add = NULL;
static EmeraldGtkWidgetShowAllFn emerald_gtk_widget_show_all = NULL;
static EmeraldGtkWidgetDestroyFn emerald_gtk_widget_destroy = NULL;
static EmeraldGtkEventsPendingFn emerald_gtk_events_pending = NULL;
static EmeraldGtkMainIterationDoFn emerald_gtk_main_iteration_do = NULL;
static EmeraldGtkMainFn emerald_gtk_main = NULL;
static EmeraldGtkMainQuitFn emerald_gtk_main_quit = NULL;
static EmeraldGtkInitFn emerald_gtk_init = NULL;
static EmeraldWebKitWebViewNewFn emerald_webkit_web_view_new = NULL;
static EmeraldWebKitWebViewLoadHtmlFn emerald_webkit_web_view_load_html = NULL;
static EmeraldWebKitNavigationPolicyDecisionGetRequestFn emerald_webkit_navigation_policy_decision_get_request = NULL;
static EmeraldWebKitUriRequestGetUriFn emerald_webkit_uri_request_get_uri = NULL;
static EmeraldWebKitPolicyDecisionIgnoreFn emerald_webkit_policy_decision_ignore = NULL;
static EmeraldGSignalConnectDataFn emerald_g_signal_connect_data = NULL;

static void emerald_ui_gtk_destroy_callback(void *widget, void *data) {
    (void) widget;

    EmeraldUiWindow *entry = (EmeraldUiWindow *) data;

    if (entry != NULL) {
        entry->visible = 0;
    }

    if (emerald_gtk_main_quit != NULL) {
        emerald_gtk_main_quit();
    }
}

static int emerald_ui_is_action_uri(const char *uri) {
    if (uri == NULL) {
        return 0;
    }

    return strncmp(uri, "emerald://action/", 17) == 0;
}

static void emerald_ui_store_action(EmeraldUiWindow *entry, const char *uri) {
    if (entry == NULL || uri == NULL) {
        return;
    }

    const char *action = uri + 17;
    size_t length = strlen(action);

    if (length >= sizeof(entry->last_action)) {
        length = sizeof(entry->last_action) - 1;
    }

    memcpy(entry->last_action, action, length);
    entry->last_action[length] = 0;
}

static int emerald_ui_webkit_decide_policy_callback(void *view, void *decision, int decision_type, void *data) {
    (void) view;
    (void) decision_type;

    EmeraldUiWindow *entry = (EmeraldUiWindow *) data;

    if (emerald_webkit_navigation_policy_decision_get_request == NULL || emerald_webkit_uri_request_get_uri == NULL) {
        return 0;
    }

    void *request = emerald_webkit_navigation_policy_decision_get_request(decision);
    const char *uri = emerald_webkit_uri_request_get_uri(request);

    if (!emerald_ui_is_action_uri(uri)) {
        return 0;
    }

    emerald_ui_store_action(entry, uri);

    if (emerald_webkit_policy_decision_ignore != NULL) {
        emerald_webkit_policy_decision_ignore(decision);
    }

    if (emerald_gtk_main_quit != NULL) {
        emerald_gtk_main_quit();
    }

    return 1;
}

static void *emerald_ui_load_symbol(void *library, const char *name) {
    if (library == NULL) {
        return NULL;
    }

    return dlsym(library, name);
}

static void *emerald_ui_open_first_library(const char **names) {
    int index = 0;

    while (names[index] != NULL) {
        void *library = dlopen(names[index], RTLD_LAZY | RTLD_GLOBAL);

        if (library != NULL) {
            return library;
        }

        index++;
    }

    return NULL;
}

static int emerald_ui_load_linux_webkitgtk(void) {
    const char *forced = getenv("EMERALD_UI_BACKEND");

    if (forced != NULL && strcmp(forced, "headless") == 0) {
        snprintf(emerald_ui_backend_name, sizeof(emerald_ui_backend_name), "%s", "linux-headless");
        return 0;
    }

    const char *gtk_names[] = {
        "libgtk-3.so.0",
        NULL
    };

    const char *gobject_names[] = {
        "libgobject-2.0.so.0",
        NULL
    };

    const char *webkit_names[] = {
        "libwebkit2gtk-4.1.so.0",
        "libwebkit2gtk-4.0.so.37",
        "libwebkit2gtk-4.0.so.0",
        NULL
    };

    emerald_ui_gtk_library = emerald_ui_open_first_library(gtk_names);
    emerald_ui_gobject_library = emerald_ui_open_first_library(gobject_names);
    emerald_ui_webkit_library = emerald_ui_open_first_library(webkit_names);

    if (emerald_ui_gtk_library == NULL || emerald_ui_gobject_library == NULL || emerald_ui_webkit_library == NULL) {
        snprintf(emerald_ui_backend_name, sizeof(emerald_ui_backend_name), "%s", "linux-headless-webkitgtk-missing");
        return 0;
    }

    emerald_gtk_init = (EmeraldGtkInitFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_init");
    emerald_gtk_window_new = (EmeraldGtkWindowNewFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_window_new");
    emerald_gtk_window_set_title = (EmeraldGtkWindowSetTitleFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_window_set_title");
    emerald_gtk_window_set_default_size = (EmeraldGtkWindowSetDefaultSizeFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_window_set_default_size");
    emerald_gtk_container_add = (EmeraldGtkContainerAddFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_container_add");
    emerald_gtk_widget_show_all = (EmeraldGtkWidgetShowAllFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_widget_show_all");
    emerald_gtk_widget_destroy = (EmeraldGtkWidgetDestroyFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_widget_destroy");
    emerald_gtk_events_pending = (EmeraldGtkEventsPendingFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_events_pending");
    emerald_gtk_main_iteration_do = (EmeraldGtkMainIterationDoFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_main_iteration_do");
    emerald_gtk_main = (EmeraldGtkMainFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_main");
    emerald_gtk_main_quit = (EmeraldGtkMainQuitFn) emerald_ui_load_symbol(emerald_ui_gtk_library, "gtk_main_quit");
    emerald_webkit_web_view_new = (EmeraldWebKitWebViewNewFn) emerald_ui_load_symbol(emerald_ui_webkit_library, "webkit_web_view_new");
    emerald_webkit_web_view_load_html = (EmeraldWebKitWebViewLoadHtmlFn) emerald_ui_load_symbol(emerald_ui_webkit_library, "webkit_web_view_load_html");
    emerald_webkit_navigation_policy_decision_get_request = (EmeraldWebKitNavigationPolicyDecisionGetRequestFn) emerald_ui_load_symbol(emerald_ui_webkit_library, "webkit_navigation_policy_decision_get_request");
    emerald_webkit_uri_request_get_uri = (EmeraldWebKitUriRequestGetUriFn) emerald_ui_load_symbol(emerald_ui_webkit_library, "webkit_uri_request_get_uri");
    emerald_webkit_policy_decision_ignore = (EmeraldWebKitPolicyDecisionIgnoreFn) emerald_ui_load_symbol(emerald_ui_webkit_library, "webkit_policy_decision_ignore");
    emerald_g_signal_connect_data = (EmeraldGSignalConnectDataFn) emerald_ui_load_symbol(emerald_ui_gobject_library, "g_signal_connect_data");

    if (emerald_gtk_init == NULL || emerald_gtk_window_new == NULL || emerald_gtk_window_set_title == NULL || emerald_gtk_window_set_default_size == NULL || emerald_gtk_container_add == NULL || emerald_gtk_widget_show_all == NULL || emerald_gtk_widget_destroy == NULL || emerald_gtk_events_pending == NULL || emerald_gtk_main_iteration_do == NULL || emerald_gtk_main == NULL || emerald_webkit_web_view_new == NULL || emerald_webkit_web_view_load_html == NULL) {
        snprintf(emerald_ui_backend_name, sizeof(emerald_ui_backend_name), "%s", "linux-headless-webkitgtk-symbol-missing");
        return 0;
    }

    emerald_gtk_init(NULL, NULL);
    snprintf(emerald_ui_backend_name, sizeof(emerald_ui_backend_name), "%s", "linux-webkitgtk-dynamic");
    return 1;
}
#endif
