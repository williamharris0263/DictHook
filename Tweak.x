#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 1. 声明要 Hook 的 C 函数原型
int sqlite3_key(void *db, const void *pKey, int nKey);

// 2. 使用 Logos 的 %hookf 语法拦截 C 函数
%hookf(int, sqlite3_key, void *db, const void *pKey, int nKey) {
    if (nKey > 0 && pKey != NULL) {
        // 将内存中的密码指针转换为 NSData 和 NSString
        NSData *keyData = [NSData dataWithBytes:pKey length:nKey];
        NSString *keyString = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
        
        // 有些密码可能是原始的 32 字节哈希值（显示乱码），所以我们将 Hex 格式也打印出来备用
        NSString *msg = [NSString stringWithFormat:@"明文密码:\n%@\n\nHex格式:\n%@", 
                        keyString ?: @"无法转为普通文本", 
                        keyData];
        
        // [方式A] 打印到系统日志
        NSLog(@"[SQLCipher Hook] 抓到数据库密码了！ ===> %@", msg);
        
        // [方式B] 将密码写入到 App 沙盒的临时目录中，防止错漏
        NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sqlcipher_password.txt"];
        [msg writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        // [方式C] 在主线程弹出一个弹窗，直接显示在屏幕上
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"[破解成功]" 
                                                                           message:msg 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            
            // 寻找当前顶层控制器弹出窗口
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            if (rootVC.presentedViewController) {
                [rootVC.presentedViewController presentViewController:alert animated:YES completion:nil];
            } else {
                [rootVC presentViewController:alert animated:YES completion:nil];
            }
        });
    }
    
    // 3. 必须调用 %orig，放行原函数，否则 App 无法正常解密数据库并崩溃
    return %orig(db, pKey, nKey);
}
