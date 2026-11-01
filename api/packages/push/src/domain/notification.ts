/**
 * A push notification, written without its words. The alert names a key in the app's String
 * Catalog (APNs `loc-key`), so the copy lives in the app, Chinese first, and changes without a
 * server release.
 */
export interface PushNotification {
  readonly alert: {
    /** The String Catalog key of the alert's text: one of the server's `PUSH_COPY`. */
    readonly key: string;
    /** Values for the key's `%@` placeholders, in order. */
    readonly args?: readonly string[];
  };
  /**
   * The notification category the app registers (`UNNotificationCategory`), which picks the
   * buttons shown on it.
   */
  readonly category: string;
  /** Notifications with the same thread are grouped together on the phone. */
  readonly thread: string;
  /**
   * A later notification with the same collapse id replaces this one on the phone instead of
   * stacking next to it. At most 64 bytes.
   */
  readonly collapseId?: string;
  /**
   * `passive` shows quietly in the notification list, with no sound and no lighting up the
   * screen; `active` is a normal notification.
   */
  readonly interruption: 'passive' | 'active';
  /**
   * Lets the app's notification service extension rewrite the alert from `event` before it is
   * shown (APNs `mutable-content`), for copy one String Catalog key can't say, such as a list of
   * counts. The alert stays as sent when the extension doesn't run.
   */
  readonly mutableContent?: boolean;
  /**
   * What happened, for the app to open and act on, e.g. `{ checkIn: "<id>" }`, or counts by kind
   * such as `{ received: { reaction: 3 } }`. APNs takes 4KB for the whole payload.
   */
  readonly event: Readonly<Record<string, EventValue>>;
}

/**
 * A value in a notification's `event`: any JSON, such as text, a number, counts by kind, or the
 * squad's posts today for the push's long-press view.
 */
export type EventValue =
  string | number | boolean | readonly EventValue[] | { readonly [key: string]: EventValue };

/** The APNs JSON payload for a notification, with the `version` every wire body carries. */
export function apnsPayload(notification: PushNotification) {
  const { alert, category, thread, interruption, mutableContent, event } = notification;
  return {
    version: 1,
    aps: {
      alert: {
        'loc-key': alert.key,
        ...(alert.args === undefined ? {} : { 'loc-args': alert.args }),
      },
      category,
      'thread-id': thread,
      'interruption-level': interruption,
      ...(interruption === 'active' ? { sound: 'default' } : {}),
      ...(mutableContent === true ? { 'mutable-content': 1 } : {}),
    },
    event,
  };
}
