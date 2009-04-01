#import <UIKit/UIKit.h>

@interface UIAlertView (Utils)

+(void)showAlertViewWithMessage: (NSString*)message;
+(void)showAlertViewWithTitle: (NSString*)title message: (NSString*)message;

+(void)showModalAlertViewWithMessage: (NSString*)message;

@end
