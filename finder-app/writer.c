#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>

int main(int argc, char *argv[]) {
    // 開啟 syslog 記錄
    openlog("writer", LOG_PID, LOG_USER);
    
    // 檢查參數數量
    if (argc != 3) {
        syslog(LOG_ERR, "Error: Two arguments required: <file path> <text to write>");
        fprintf(stderr, "Usage: %s <file path> <text to write>\n", argv[0]);
        closelog();
        return 1;
    }
    
    const char *filepath = argv[1];
    const char *text = argv[2];
    
    // 打開文件以寫入 (覆蓋模式)
    FILE *file = fopen(filepath, "w");
    if (file == NULL) {
        syslog(LOG_ERR, "Error: Could not open file '%s' for writing", filepath);
        perror("Error opening file");
        closelog();
        return 1;
    }
    
    // 寫入內容
    if (fprintf(file, "%s", text) < 0) {
        syslog(LOG_ERR, "Error: Could not write to file '%s'", filepath);
        perror("Error writing to file");
        fclose(file);
        closelog();
        return 1;
    }
    
    // 關閉文件
    fclose(file);
    
    // 記錄 syslog
    syslog(LOG_DEBUG, "Writing '%s' to '%s'", text, filepath);
    
    closelog();
    return 0;
}
