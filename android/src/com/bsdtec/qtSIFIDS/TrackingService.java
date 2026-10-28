package com.bsdtec.qtSIFIDS;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

// Foreground service that keeps the process (and Qt's location updates) alive in the background.
public class TrackingService extends Service {
    private static final String CHANNEL_ID = "sifids_tracking";
    private static final int NOTIFICATION_ID = 1;
    private PowerManager.WakeLock wakeLock;

    public static void start(Activity activity) {
        if (Build.VERSION.SDK_INT >= 33
                && activity.checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                        != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(new String[] {"android.permission.POST_NOTIFICATIONS"}, 0);
        }
        Intent intent = new Intent(activity, TrackingService.class);
        try {
            activity.startForegroundService(intent);
        } catch (RuntimeException e) {
            // Not allowed to start from the background; tracking continues in the foreground only.
        }
    }

    public static void stop(Activity activity) {
        activity.stopService(new Intent(activity, TrackingService.class));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(new NotificationChannel(
                    CHANNEL_ID, "Tracking", NotificationManager.IMPORTANCE_LOW));
        }

        Intent launch = new Intent(this, org.qtproject.qt.android.bindings.QtActivity.class);
        launch.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pending = PendingIntent.getActivity(
                this, 0, launch, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        Notification notification = builder
                .setContentTitle("SIFIDS")
                .setContentText("Tracking location in the background")
                .setSmallIcon(getApplicationInfo().icon)
                .setContentIntent(pending)
                .setOngoing(true)
                .build();

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }

        if (wakeLock == null) {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "qtSIFIDS:tracking");
            wakeLock.acquire();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (wakeLock != null && wakeLock.isHeld())
            wakeLock.release();
        wakeLock = null;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
