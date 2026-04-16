#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import "fishhook.h"

// ==========================================
// 目标一：数据库明文密码全量拦截 (保留)
// ==========================================
static NSMutableArray *allCapturedDbKeys;
static int (*original_sqlite3_key)(void *db, const void *pKey, int nKey);

static int replaced_sqlite3_key(void *db, const void *pKey, int nKey) {
    if (nKey > 0 && pKey != NULL) {
        if (!allCapturedDbKeys) allCapturedDbKeys = [[NSMutableArray alloc] init];
        
        NSData *keyData = [NSData dataWithBytes:pKey length:nKey];
        NSString *keyString = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
        
        NSString *dbPathStr = @"[未知数据库路径]";
        const char *(*dynamic_sqlite3_db_filename)(void *, const char *) = dlsym(RTLD_DEFAULT, "sqlite3_db_filename");
        if (dynamic_sqlite3_db_filename != NULL) {
            const char *dbPath = dynamic_sqlite3_db_filename(db, "main");
            if (dbPath != NULL) dbPathStr = [NSString stringWithUTF8String:dbPath];
        }
        
        NSString *msg = [NSString stringWithFormat:@"📂 数据库: %@\n🔑 明文: %@\n🧬 Hex: %@", 
                        dbPathStr.lastPathComponent ?: dbPathStr, keyString ?: @"[无法转码]", keyData];
        
        if (![allCapturedDbKeys containsObject:msg]) {
            [allCapturedDbKeys addObject:msg];
            NSString *finalOutput = [allCapturedDbKeys componentsJoinedByString:@"\n----------------------\n"];
            
            NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            [finalOutput writeToFile:[docPath stringByAppendingPathComponent:@"sqlcipher_all_keys.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
    return original_sqlite3_key(db, pKey, nKey);
}

// ==========================================
// 目标二：突破“阅后即焚” (抢夺物理文件)
// ==========================================
static void backupHTMLFile(NSString *htmlString, NSString *originalName) {
    if (!htmlString || htmlString.length == 0) return;

    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *saveDir = [docPath stringByAppendingPathComponent:@"DecryptedHTML_Backup"];
    [[NSFileManager defaultManager] createDirectoryAtPath:saveDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    // 保存名字：原文件名_时间戳.html
    NSString *finalName = [NSString stringWithFormat:@"%@_%ld.html", originalName, (long)now];
    NSString *filePath = [saveDir stringByAppendingPathComponent:finalName];

    [htmlString writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[DictHook] 抢夺成功！已备份: %@", finalName);
}

%hook WKWebView

// 1. 拦截直接传字符串的情况 (向下兼容)
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    backupHTMLFile(string, baseURL ? baseURL.lastPathComponent : @"StringLoad");
    return %orig(string, baseURL);
}

// 2. 拦截“阅后即焚”的物理文件加载 (核心绝杀点！)
- (WKNavigation *)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL {
    // 此时文件必定还存在于磁盘上，因为还要交给 WebView 渲染
    if (URL && URL.isFileURL) {
        NSString *filePath = URL.path;
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            // 在 App 删除它之前，瞬间把它读出来！
            NSError *error;
            NSString *htmlContent = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
            if (htmlContent) {
                // 提取文件的原名 (比如随机目录外的名字)
                backupHTMLFile(htmlContent, URL.lastPathComponent);
            }
        }
    }
    return %orig(URL, readAccessURL);
}

%end

// ==========================================
// 初始化
// ==========================================
%ctor {
    struct rebinding sql_reb;
    sql_reb.name = "sqlite3_key";
    sql_reb.replacement = (void *)replaced_sqlite3_key;
    sql_reb.replaced = (void **)&original_sqlite3_key;
    rebind_symbols((struct rebinding[1]){sql_reb}, 1);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *topVC = keyWindow.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🚀 反阅后即焚已开启" 
                                                                       message:@"已侦测到 App 可能使用了‘随机目录+阅后即焚’机制。\n\n请点击任意词条。\n插件将在文件被销毁前瞬间完成物理抢夺！\n结果保存在 DecryptedHTML_Backup 目录。" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"去点单词" style:UIAlertActionStyleDefault handler:nil]];
        if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
    });
}
