const std = @import("std");

/// Можливі стани контейнера згідно з OCI специфікацією
pub const State = enum {
    /// Контейнер створено, але ще не запущено
    created,
    /// Контейнер запущений і працює
    running,
    /// Контейнер зупинений
    stopped,
    /// Контейнер призупинений
    paused,
    /// Контейнер знаходиться в процесі видалення
    deleting,
};

/// Помилки, які можуть виникнути при роботі зі станом контейнера
pub const StateError = error{
    /// Неможливий перехід між станами
    InvalidStateTransition,
    /// Контейнер вже знаходиться в цільовому стані
    AlreadyInState,
    /// Помилка при збереженні стану
    SaveError,
    /// Помилка при завантаженні стану
    LoadError,
};

/// Структура для зберігання стану контейнера
pub const ContainerState = struct {
    /// Поточний стан контейнера
    state: State,
    
    /// Час створення контейнера (в наносекундах від епохи)
    created: i128,
    
    /// Час запуску контейнера (в наносекундах від епохи)
    started: ?i128,
    
    /// Час зупинки контейнера (в наносекундах від епохи)
    finished: ?i128,
    
    /// Код виходу процесу контейнера
    exit_code: ?i32,
    
    /// Причина зупинки контейнера
    exit_reason: ?[]const u8,
    
    /// PID головного процесу контейнера
    pid: ?i32,

    const Self = @This();

    /// Створює новий стан контейнера
    pub fn init() Self {
        return Self{
            .state = .created,
            .created = std.time.nanoTimestamp(),
            .started = null,
            .finished = null,
            .exit_code = null,
            .exit_reason = null,
            .pid = null,
        };
    }

    /// Перевіряє, чи можливий перехід між станами
    pub fn canTransitionTo(self: Self, target_state: State) bool {
        return switch (self.state) {
            .created => switch (target_state) {
                .running, .deleting => true,
                else => false,
            },
            .running => switch (target_state) {
                .stopped, .paused, .deleting => true,
                else => false,
            },
            .stopped => switch (target_state) {
                .deleting => true,
                else => false,
            },
            .paused => switch (target_state) {
                .running, .deleting => true,
                else => false,
            },
            .deleting => false,
        };
    }

    /// Виконує перехід до нового стану
    pub fn transitionTo(self: *Self, target_state: State) StateError!void {
        if (self.state == target_state) {
            return StateError.AlreadyInState;
        }

        if (!self.canTransitionTo(target_state)) {
            return StateError.InvalidStateTransition;
        }

        // Оновлюємо часові мітки та інші поля в залежності від переходу
        switch (target_state) {
            .running => {
                self.started = std.time.nanoTimestamp();
                self.finished = null;
                self.exit_code = null;
                self.exit_reason = null;
            },
            .stopped => {
                self.finished = std.time.nanoTimestamp();
            },
            .paused => {},
            .created => unreachable,
            .deleting => {},
        }

        self.state = target_state;
    }

    /// Встановлює PID головного процесу контейнера
    pub fn setPid(self: *Self, pid: i32) void {
        self.pid = pid;
    }

    /// Встановлює код виходу та причину зупинки
    pub fn setExit(self: *Self, code: i32, reason: ?[]const u8) void {
        self.exit_code = code;
        self.exit_reason = reason;
    }
}; 