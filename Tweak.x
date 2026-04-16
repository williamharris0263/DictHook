#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import "fishhook.h"

// ==========================================
// 目标一：数据库明文密码全量拦截 (Fishhook)
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
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIPasteboard generalPasteboard].string = finalOutput;
            });
        }
    }
    return original_sqlite3_key(db, pKey, nKey);
}

// ==========================================
// 目标二：HTML 网页渲染拦截 (Logos)
// ==========================================
static void saveDecryptedHTML(NSString *html, NSURL *baseURL) {
    if (!html || html.length == 0) return;

    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *saveDir = [docPath stringByAppendingPathComponent:@"DecryptedHTML"];
    [[NSFileManager defaultManager] createDirectoryAtPath:saveDir withIntermediateDirectories:YES attributes:nil error:nil];

    // 尝试从 baseURL 提取原始名称，若无则使用时间戳
    NSString *originalFileName = @"UnknownEntry";
    if (baseURL && baseURL.lastPathComponent && baseURL.lastPathComponent.length > 0) {
        originalFileName = baseURL.lastPathComponent;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *finalName = [NSString stringWithFormat:@"%@_%ld.html", originalFileName, (long)now];
    NSString *filePath = [saveDir stringByAppendingPathComponent:finalName];

    [html writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%hook WKWebView
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    saveDecryptedHTML(string, baseURL);
    return %orig(string, baseURL);
}
- (WKNavigation *)loadData:(NSData *)data MIMEType:(NSString *)MIMEType characterEncodingName:(NSString *)encoding baseURL:(NSURL *)baseURL {
    if ([MIMEType containsString:@"html"]) {
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        saveDecryptedHTML(html, baseURL);
    }
    return %orig(data, MIMEType, encoding, baseURL);
}
%end

// ==========================================
// 目标三：内存切片狙击解密母包 (Logos) - 已降低门槛
// ==========================================
%hook NSData
- (NSData *)subdataWithRange:(NSRange)range {
    // 狙击条件：母体数据大于10KB (适配你列表里的小文件)，且切片在合理范围内
    if (self.length > 10000 && range.length > 50 && range.length < 80000) {
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dumpDir = [docPath stringByAppendingPathComponent:@"DecryptedPacks"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dumpDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        // 使用该内存块的准确字节数作为文件名标识
        NSString *fileName = [NSString stringWithFormat:@"DecryptedPack_%lu_bytes.bin", (unsigned long)self.length];
        NSString *savePath = [dumpDir stringByAppendingPathComponent:fileName];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:savePath]) {
            [self writeToFile:savePath atomically:YES];
            NSLog(@"[DictHook] 狙击成功！截获数据母包: %@", fileName);
        }
    }
    return %orig(range);
}
%end

// ==========================================
// 初始化与全量挂载
// ==========================================
%ctor {
    // 挂载数据库 Fishhook
    struct rebinding sql_reb;
    sql_reb.name = "sqlite3_key";
    sql_reb.replacement = (void *)replaced_sqlite3_key;
    sql_reb.replaced = (void **)&original_sqlite3_key;
    rebind_symbols((struct rebinding[1]){sql_reb}, 1);
    
    // 启动 5 秒后的安全状态提示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *topVC = keyWindow.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🛡️ 终极逆向核心已注入" 
                                                                       message:@"功能状态：\n1. 所有 DB 数据库密码监控中\n2. WKWebView 网页 HTML 监控中\n3. 内存切片数据母包狙击中 (门槛 10KB)\n\n请随意查询首字母不同的单词。所有文件将导出到沙盒 Documents 目录下。" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"冲！" style:UIAlertActionStyleDefault handler:nil]];
        if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
    });
}
