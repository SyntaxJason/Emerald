#define EMERALD_UI_MAX_WINDOWS 128

#if defined(_WIN32)
typedef struct EventRegistrationToken {
    int64_t value;
} EventRegistrationToken;
#endif

typedef struct EmeraldUiWindow {
    int used;
    int visible;
    int width;
    int height;
    EmeraldString *title;
    EmeraldString *html;
    char last_action[256];
    char preview_path[4096];
    int browser_opened;
    void *native_window;
    void *native_view;
#if defined(_WIN32)
    SOCKET server_socket;
    HANDLE server_thread;
    DWORD server_thread_id;
    int server_port;
    volatile LONG server_running;
    void *webview2_environment;
    void *webview2_controller;
    void *webview2_webview;
    void *webview2_environment_handler;
    void *webview2_controller_handler;
    void *webview2_navigation_handler;
    EventRegistrationToken webview2_navigation_token;
    int webview2_requested;
    int webview2_ready;
    int webview2_failed;
#endif
} EmeraldUiWindow;

static EmeraldUiWindow emerald_ui_windows[EMERALD_UI_MAX_WINDOWS];
static int emerald_ui_initialized = 0;
static int emerald_ui_backend_ready = 0;
static char emerald_ui_backend_name[128] = "headless";
