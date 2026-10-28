#include <QString>

#import <UIKit/UIKit.h>

// Presents the standard iOS share sheet (UIActivityViewController) with the sail
// plan / check-in text so the user can pick Messages, Mail, WhatsApp, etc. and a
// contact at send time. UIActivityViewController has no separate subject field for
// plain-text sharing, so the subject is folded into the shared text.
void sifidsPresentShareSheet(const QString &subject, const QString &body)
{
    NSString *text = subject.isEmpty()
        ? body.toNSString()
        : [NSString stringWithFormat:@"%@\n\n%@", subject.toNSString(), body.toNSString()];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = nil;
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        root = window.rootViewController;
                        break;
                    }
                }
            }
            if (root)
                break;
        }
        if (!root)
            return;
        while (root.presentedViewController)
            root = root.presentedViewController;

        UIActivityViewController *activityController = [[UIActivityViewController alloc]
            initWithActivityItems:@[ text ] applicationActivities:nil];
        if (activityController.popoverPresentationController) {
            activityController.popoverPresentationController.sourceView = root.view;
            activityController.popoverPresentationController.sourceRect =
                CGRectMake(root.view.bounds.size.width / 2.0, root.view.bounds.size.height, 1, 1);
        }
        [root presentViewController:activityController animated:YES completion:nil];
    });
}
