package main

import (
	"bytes"
	"database/sql"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
)

type DbCreds struct {
	Host     string `json:"host"`
	Port     string `json:"port"`
	User     string `json:"user"`
	Password string `json:"password"`
}

var globalCreds *DbCreds

func saveCredentialsToCache(creds *DbCreds) {
	// Deactivated for security reasons. Credentials are saved in client-side SharedPreferences.
}

func loadCredentialsFromCache() {
	// Clean up legacy cache files for security
	if _, err := os.Stat("creds_cache.json"); err == nil {
		_ = os.Remove("creds_cache.json")
	}
}

// Helper to backup a single database using mysqldump
func runMysqldump(creds *DbCreds, dbName, targetDir, filename string) error {
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return fmt.Errorf("failed to create directory %s: %v", targetDir, err)
	}

	destPath := filepath.Join(targetDir, filename)

	args := []string{
		"-h", creds.Host,
		"-P", creds.Port,
		"-u", creds.User,
	}
	if creds.Password != "" {
		args = append(args, "-p"+creds.Password)
	}
	args = append(args, "--routines", "--triggers", "--events", dbName)

	cmd := exec.Command("mysqldump", args...)

	outFile, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("failed to create backup file %s: %v", destPath, err)
	}
	defer outFile.Close()

	cmd.Stdout = outFile
	var errBuf bytes.Buffer
	cmd.Stderr = &errBuf

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("mysqldump failed for %s: %v, stderr: %s", dbName, err, errBuf.String())
	}
	return nil
}

// Helper to restore a database from an SQL file
func runMysqlRestore(creds *DbCreds, dbName, filePath string) error {
	args := []string{
		"-h", creds.Host,
		"-P", creds.Port,
		"-u", creds.User,
	}
	if creds.Password != "" {
		args = append(args, "-p"+creds.Password)
	}
	args = append(args, dbName)

	cmd := exec.Command("mysql", args...)

	inFile, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open sql file %s: %v", filePath, err)
	}
	defer inFile.Close()

	cmd.Stdin = inFile
	var errBuf bytes.Buffer
	cmd.Stderr = &errBuf

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("mysql restore failed: %v, stderr: %s", err, errBuf.String())
	}
	return nil
}

// Helper to cleanup backups older than keepDays
func cleanupOldBackups(keepDays int) {
	if keepDays <= 0 {
		return
	}
	files, err := os.ReadDir("backup")
	if err != nil {
		return
	}
	cutoff := time.Now().AddDate(0, 0, -keepDays)
	for _, f := range files {
		if f.IsDir() && f.Name() != "copy_backup" {
			parts := strings.Split(f.Name(), "_")
			if len(parts) >= 1 {
				t, err := time.Parse("20060102", parts[0])
				if err == nil {
					if t.Before(cutoff) {
						os.RemoveAll(filepath.Join("backup", f.Name()))
					}
				}
			}
		}
	}
}

func timeMatches(configTime string, now time.Time) bool {
	configTime = strings.TrimSpace(configTime)
	parts := strings.Split(configTime, ":")
	if len(parts) != 2 {
		return false
	}
	cfgHour, err1 := strconv.Atoi(parts[0])
	cfgMin, err2 := strconv.Atoi(parts[1])
	if err1 != nil || err2 != nil {
		return false
	}

	nowHour := now.Hour()
	nowMin := now.Minute()

	if cfgMin != nowMin {
		return false
	}

	// Match hour (handling 12 AM vs 00:xx ambiguity)
	if cfgHour == nowHour {
		return true
	}
	if (cfgHour == 12 && nowHour == 0) || (cfgHour == 0 && nowHour == 12) {
		return true
	}

	return false
}

// Background Scheduler for Auto Backups
func startAutoBackupScheduler() {
	ticker := time.NewTicker(1 * time.Minute)
	go func() {
		for range ticker.C {
			if globalCreds == nil {
				continue
			}

			dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/mysql?charset=utf8mb4&parseTime=True&loc=Local",
				globalCreds.User, globalCreds.Password, globalCreds.Host, globalCreds.Port)
			db, err := sql.Open("mysql", dsn)
			if err != nil {
				continue
			}

			if err := db.Ping(); err != nil {
				db.Close()
				continue
			}

			_, _ = db.Exec(`CREATE TABLE IF NOT EXISTS auto_backup (
				db_name VARCHAR(255) PRIMARY KEY,
				backup_time VARCHAR(5) NOT NULL,
				keep_days INT NOT NULL,
				is_active TINYINT DEFAULT 1
			);`)

			rows, err := db.Query("SELECT db_name, backup_time, keep_days FROM auto_backup WHERE is_active = 1;")
			if err != nil {
				db.Close()
				continue
			}

			now := time.Now()

			var backupsToRun []struct {
				dbName   string
				keepDays int
			}

			for rows.Next() {
				var dbName, backupTime string
				var keepDays int
				if err := rows.Scan(&dbName, &backupTime, &keepDays); err == nil {
					if timeMatches(backupTime, now) {
						backupsToRun = append(backupsToRun, struct {
							dbName   string
							keepDays int
						}{dbName, keepDays})
					}
				}
			}
			rows.Close()
			db.Close()

			if len(backupsToRun) > 0 {
				dirName := now.Format("20060102_150405")
				targetDir := filepath.Join("backup", dirName)

				for _, backup := range backupsToRun {
					_ = runMysqldump(globalCreds, backup.dbName, targetDir, backup.dbName+".sql")
					cleanupOldBackups(backup.keepDays)
				}
			}
		}
	}()
}

// DBConnection credentials dynamic header parser
func getDSN(c *gin.Context, overrideDb string) (string, error) {
	host := c.GetHeader("X-DB-Host")
	port := c.GetHeader("X-DB-Port")
	user := c.GetHeader("X-DB-User")
	password := c.GetHeader("X-DB-Password")
	database := c.GetHeader("X-DB-Database")

	if overrideDb != "" {
		database = overrideDb
	}

	if host == "" || user == "" {
		return "", fmt.Errorf("X-DB-Host and X-DB-User headers are required")
	}
	if port == "" {
		port = "3306"
	}

	var dsn string
	// Go MySQL driver DSN format: user:password@tcp(host:port)/dbname?charset=utf8mb4&parseTime=True&loc=Local
	if password != "" {
		dsn = fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local", user, password, host, port, database)
	} else {
		dsn = fmt.Sprintf("%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local", user, host, port, database)
	}
	return dsn, nil
}

func getDBConnection(c *gin.Context, database string) (*sql.DB, error) {
	dsn, err := getDSN(c, database)
	if err != nil {
		return nil, err
	}
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, err
	}
	// Verify connection
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func quoteIdentifier(val string) string {
	escaped := strings.ReplaceAll(val, "'", "''")
	return fmt.Sprintf("'%s'", escaped)
}

// Split multi-queries by semicolon, ignoring semicolons inside quotes.
func splitSQLQueries(sqlStr string) []string {
	var queries []string
	var currentQuery []rune
	inSingleQuote := false
	inDoubleQuote := false
	inBacktick := false
	escaped := false

	runes := []rune(sqlStr)
	for i := 0; i < len(runes); i++ {
		char := runes[i]
		if escaped {
			currentQuery = append(currentQuery, char)
			escaped = false
			continue
		}
		if char == '\\' {
			currentQuery = append(currentQuery, char)
			escaped = true
			continue
		}
		if char == '\'' && !inDoubleQuote && !inBacktick {
			inSingleQuote = !inSingleQuote
		} else if char == '"' && !inSingleQuote && !inBacktick {
			inDoubleQuote = !inDoubleQuote
		} else if char == '`' && !inSingleQuote && !inDoubleQuote {
			inBacktick = !inBacktick
		}

		if char == ';' && !inSingleQuote && !inDoubleQuote && !inBacktick {
			q := strings.TrimSpace(string(currentQuery))
			if q != "" {
				queries = append(queries, q)
			}
			currentQuery = nil
		} else {
			currentQuery = append(currentQuery, char)
		}
	}

	q := strings.TrimSpace(string(currentQuery))
	if q != "" {
		queries = append(queries, q)
	}
	return queries
}

func compileColumnDef(col map[string]interface{}) string {
	name, _ := col["field_name"].(string)
	dtype, _ := col["data_type"].(string)
	isAi, _ := col["is_ai"].(bool)
	comment, _ := col["comment"].(string)

	spec := fmt.Sprintf("`%s` %s", name, dtype)

	dtypeLower := strings.ToLower(dtype)
	isSizeAllowed := false
	if strings.Contains(dtypeLower, "char") ||
		strings.Contains(dtypeLower, "binary") ||
		strings.Contains(dtypeLower, "decimal") ||
		strings.Contains(dtypeLower, "numeric") ||
		dtypeLower == "bit" {
		isSizeAllowed = true
	}

	// Add size if exists and is allowed for the type
	if isSizeAllowed {
		if sizeVal, ok := col["data_size"]; ok && sizeVal != nil {
			var sizeStr string
			switch v := sizeVal.(type) {
			case float64:
				sizeStr = strconv.FormatFloat(v, 'f', -1, 64)
			case int:
				sizeStr = strconv.Itoa(v)
			case string:
				sizeStr = v
			}

			if sizeStr != "" && strings.TrimSpace(sizeStr) != "" {
				if scaleVal, ok := col["decimal_places"]; ok && scaleVal != nil {
					var scaleStr string
					switch v := scaleVal.(type) {
					case float64:
						scaleStr = strconv.FormatFloat(v, 'f', -1, 64)
					case int:
						scaleStr = strconv.Itoa(v)
					case string:
						scaleStr = v
					}
					if scaleStr != "" && strings.TrimSpace(scaleStr) != "" {
						spec += fmt.Sprintf("(%s,%s)", sizeStr, scaleStr)
					} else {
						spec += fmt.Sprintf("(%s)", sizeStr)
					}
				} else {
					spec += fmt.Sprintf("(%s)", sizeStr)
				}
			}
		}
	}

	if isAi {
		spec += " AUTO_INCREMENT"
	}

	if comment != "" {
		safeComment := strings.ReplaceAll(comment, "'", "''")
		spec += fmt.Sprintf(" COMMENT '%s'", safeComment)
	}

	return spec
}

func main() {
	// Parse CLI port flag
	portPtr := flag.Int("port", 10001, "Port to run the REST server on")
	flag.Parse()

	// Load cached credentials & start backup scheduler
	loadCredentialsFromCache()
	startAutoBackupScheduler()

	// Initialize Gin router
	r := gin.Default()

	// CORS configuration matching Flask backend
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "X-DB-Host", "X-DB-Port", "X-DB-User", "X-DB-Password", "X-DB-Database"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// Endpoints
	r.POST("/api/connect", func(c *gin.Context) {
		db, err := getDBConnection(c, "")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		// Cache successful connection credentials
		host := c.GetHeader("X-DB-Host")
		port := c.GetHeader("X-DB-Port")
		user := c.GetHeader("X-DB-User")
		password := c.GetHeader("X-DB-Password")
		globalCreds = &DbCreds{
			Host:     host,
			Port:     port,
			User:     user,
			Password: password,
		}
		saveCredentialsToCache(globalCreds)

		rows, err := db.Query("SHOW DATABASES;")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		var databases []string
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err == nil {
				databases = append(databases, name)
			}
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "databases": databases})
	})

	r.GET("/api/databases", func(c *gin.Context) {
		db, err := getDBConnection(c, "")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		rows, err := db.Query("SHOW DATABASES;")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		var databases []string
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err == nil {
				databases = append(databases, name)
			}
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "databases": databases})
	})

	r.GET("/api/tables", func(c *gin.Context) {
		dbName := c.Query("database")
		if dbName == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "database parameter is required"})
			return
		}

		db, err := getDBConnection(c, dbName)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		rows, err := db.Query("SHOW TABLES;")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		var tables []string
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err == nil {
				tables = append(tables, name)
			}
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "tables": tables})
	})

	r.GET("/api/search-schema", func(c *gin.Context) {
		searchQuery := c.Query("query")
		if searchQuery == "" {
			c.JSON(http.StatusOK, gin.H{"success": true, "results": []gin.H{}})
			return
		}

		db, err := getDBConnection(c, "information_schema")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		sqlQuery := `
			SELECT DISTINCT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME 
			FROM information_schema.COLUMNS 
			WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
			  AND (
				TABLE_SCHEMA LIKE ? 
				OR TABLE_NAME LIKE ? 
				OR COLUMN_NAME LIKE ?
			  )
			ORDER BY TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME LIMIT 1000;`

		likePattern := "%" + searchQuery + "%"
		rows, err := db.Query(sqlQuery, likePattern, likePattern, likePattern)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		type SearchResult struct {
			Database string `json:"database"`
			Table    string `json:"table"`
			Column   string `json:"column"`
		}

		var results []SearchResult
		for rows.Next() {
			var r SearchResult
			if err := rows.Scan(&r.Database, &r.Table, &r.Column); err == nil {
				results = append(results, r)
			}
		}

		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"results": results,
		})
	})

	r.GET("/api/columns", func(c *gin.Context) {
		dbName := c.Query("database")
		tableName := c.Query("table")
		if dbName == "" || tableName == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "database and table parameters are required"})
			return
		}

		db, err := getDBConnection(c, dbName)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		query := `
			SELECT 
				COLUMN_NAME as field_name,
				DATA_TYPE as data_type,
				CHARACTER_MAXIMUM_LENGTH as character_max_length,
				NUMERIC_PRECISION as numeric_precision,
				NUMERIC_SCALE as numeric_scale,
				COLUMN_KEY as column_key,
				EXTRA as extra,
				COLUMN_COMMENT as comment
			FROM information_schema.COLUMNS 
			WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
			ORDER BY ORDINAL_POSITION;`

		rows, err := db.Query(query, dbName, tableName)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		type colResponse struct {
			FieldName     string      `json:"field_name"`
			DataType      string      `json:"data_type"`
			DataSize      interface{} `json:"data_size"`
			DecimalPlaces interface{} `json:"decimal_places"`
			IsPk          bool        `json:"is_pk"`
			IsAi          bool        `json:"is_ai"`
			Comment       string      `json:"comment"`
		}

		var columns []colResponse
		for rows.Next() {
			var fieldName string
			var dataType string
			var charLen sql.NullInt64
			var numPrec sql.NullInt64
			var numScale sql.NullInt64
			var colKey string
			var extra string
			var comment string

			err := rows.Scan(&fieldName, &dataType, &charLen, &numPrec, &numScale, &colKey, &extra, &comment)
			if err != nil {
				continue
			}

			var dataSize interface{}
			if charLen.Valid {
				dataSize = charLen.Int64
			} else if numPrec.Valid {
				dataSize = numPrec.Int64
			}

			var decimalPlaces interface{}
			if numScale.Valid {
				decimalPlaces = numScale.Int64
			}

			columns = append(columns, colResponse{
				FieldName:     fieldName,
				DataType:      dataType,
				DataSize:      dataSize,
				DecimalPlaces: decimalPlaces,
				IsPk:          colKey == "PRI",
				IsAi:          strings.Contains(strings.ToLower(extra), "auto_increment"),
				Comment:       comment,
			})
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "columns": columns})
	})

	r.GET("/api/query-history", func(c *gin.Context) {
		startDate := c.Query("start_date")
		endDate := c.Query("end_date")
		keyword := c.Query("keyword")

		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		_, _ = db.Exec(`CREATE TABLE IF NOT EXISTS query_history (
			id INT AUTO_INCREMENT PRIMARY KEY,
			query_text LONGTEXT NOT NULL,
			executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			mysql_user VARCHAR(100) NOT NULL,
			execution_result TEXT NOT NULL,
			execution_time DOUBLE NOT NULL,
			success TINYINT(1) NOT NULL
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;`)

		sqlQuery := "SELECT id, query_text, executed_at, mysql_user, execution_result, execution_time, success FROM query_history WHERE 1=1"
		var args []interface{}

		if startDate != "" {
			sqlQuery += " AND executed_at >= ?"
			args = append(args, startDate+" 00:00:00")
		}
		if endDate != "" {
			sqlQuery += " AND executed_at <= ?"
			args = append(args, endDate+" 23:59:59")
		}
		if keyword != "" {
			sqlQuery += " AND query_text LIKE ?"
			args = append(args, "%"+keyword+"%")
		}

		sqlQuery += " ORDER BY executed_at DESC LIMIT 500;"

		rows, err := db.Query(sqlQuery, args...)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		type HistoryItem struct {
			ID              int     `json:"id"`
			QueryText       string  `json:"query_text"`
			ExecutedAt      string  `json:"executed_at"`
			MysqlUser       string  `json:"mysql_user"`
			ExecutionResult string  `json:"execution_result"`
			ExecutionTime   float64 `json:"execution_time"`
			Success         bool    `json:"success"`
		}

		var list []HistoryItem = []HistoryItem{}
		for rows.Next() {
			var item HistoryItem
			var executedAt time.Time
			var successInt int
			err := rows.Scan(&item.ID, &item.QueryText, &executedAt, &item.MysqlUser, &item.ExecutionResult, &item.ExecutionTime, &successInt)
			if err == nil {
				item.ExecutedAt = executedAt.Format("2006-01-02 15:04:05")
				item.Success = successInt == 1
				list = append(list, item)
			}
		}

		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"history": list,
		})
	})

	saveQueryHistory := func(c *gin.Context, query string, duration float64, success bool, resultMsg string) {
		db, err := getDBConnection(c, "mysql")
		if err != nil {
			fmt.Printf("Failed to connect to mysql db for history logging: %v\n", err)
			return
		}
		defer db.Close()

		_, _ = db.Exec(`CREATE TABLE IF NOT EXISTS query_history (
			id INT AUTO_INCREMENT PRIMARY KEY,
			query_text LONGTEXT NOT NULL,
			executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			mysql_user VARCHAR(100) NOT NULL,
			execution_result TEXT NOT NULL,
			execution_time DOUBLE NOT NULL,
			success TINYINT(1) NOT NULL
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;`)

		mysqlUser := c.GetHeader("X-DB-User")
		if mysqlUser == "" {
			mysqlUser = "unknown"
		}

		successVal := 0
		if success {
			successVal = 1
		}

		_, err = db.Exec(`INSERT INTO query_history (query_text, mysql_user, execution_result, execution_time, success) 
			VALUES (?, ?, ?, ?, ?);`, query, mysqlUser, resultMsg, duration, successVal)
		if err != nil {
			fmt.Printf("Failed to insert query history: %v\n", err)
		}
	}

	r.POST("/api/query", func(c *gin.Context) {
		var req struct {
			Query    string `json:"query"`
			Database string `json:"database"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		dbName := req.Database
		if dbName == "" {
			dbName = c.GetHeader("X-DB-Database")
		}

		db, err := getDBConnection(c, dbName)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Connection failed: %v", err)})
			return
		}
		defer db.Close()

		queries := splitSQLQueries(req.Query)
		var results []gin.H
		var logs []gin.H

		// Transaction-like sequential execution
		tx, err := db.Begin()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
			return
		}

		aborted := false
		for _, q := range queries {
			q = strings.TrimSpace(q)
			if q == "" {
				continue
			}

			startTime := time.Now()
			timestamp := startTime.Format("2006-01-02 15:04:05")
			logEntry := gin.H{
				"timestamp": timestamp,
				"query":     q,
			}

			// Decide if SELECT or write query
			qUpper := strings.ToUpper(q)
			isSelect := strings.HasPrefix(qUpper, "SELECT") ||
				strings.HasPrefix(qUpper, "SHOW") ||
				strings.HasPrefix(qUpper, "DESCRIBE") ||
				strings.HasPrefix(qUpper, "EXPLAIN")

			if isSelect {
				rows, queryErr := tx.Query(q)
				duration := time.Since(startTime).Seconds()
				logEntry["duration"] = fmt.Sprintf("%.3fs", duration)

				if queryErr != nil {
					tx.Rollback()
					logEntry["status"] = "ERROR"
					logEntry["message"] = queryErr.Error()
					logs = append(logs, logEntry)
					results = append(results, gin.H{
						"query":          q,
						"success":        false,
						"error":          queryErr.Error(),
						"execution_time": duration,
					})
					aborted = true
					break
				}

				cols, _ := rows.Columns()
				scanArgs := make([]interface{}, len(cols))
				values := make([]interface{}, len(cols))
				for i := range values {
					scanArgs[i] = &values[i]
				}

				var resultRows []map[string]interface{}
				for rows.Next() {
					if scanErr := rows.Scan(scanArgs...); scanErr == nil {
						rowMap := make(map[string]interface{})
						for i, colName := range cols {
							val := values[i]
							if val == nil {
								rowMap[colName] = nil
							} else if byteSlice, ok := val.([]byte); ok {
								rowMap[colName] = string(byteSlice)
							} else {
								rowMap[colName] = val
							}
						}
						resultRows = append(resultRows, rowMap)
					}
				}
				rows.Close()

				logEntry["status"] = "SUCCESS"
				logEntry["message"] = fmt.Sprintf("%d rows retrieved", len(resultRows))
				logs = append(logs, logEntry)

				results = append(results, gin.H{
					"query":          q,
					"success":        true,
					"type":           "select",
					"columns":        cols,
					"rows":           resultRows,
					"affected_rows":  len(resultRows),
					"execution_time": duration,
				})
			} else {
				res, execErr := tx.Exec(q)
				duration := time.Since(startTime).Seconds()
				logEntry["duration"] = fmt.Sprintf("%.3fs", duration)

				if execErr != nil {
					tx.Rollback()
					logEntry["status"] = "ERROR"
					logEntry["message"] = execErr.Error()
					logs = append(logs, logEntry)
					results = append(results, gin.H{
						"query":          q,
						"success":        false,
						"error":          execErr.Error(),
						"execution_time": duration,
					})
					aborted = true
					break
				}

				affected, _ := res.RowsAffected()
				logEntry["status"] = "SUCCESS"
				logEntry["message"] = fmt.Sprintf("OK, %d rows affected", affected)
				logs = append(logs, logEntry)

				results = append(results, gin.H{
					"query":          q,
					"success":        true,
					"type":           "write",
					"affected_rows":  affected,
					"execution_time": duration,
				})
			}
		}

		// Log histories in background
		go func(ctx *gin.Context, resList []gin.H) {
			for _, res := range resList {
				qText, _ := res["query"].(string)
				qSuccess, _ := res["success"].(bool)
				qDuration, _ := res["execution_time"].(float64)

				qMsg := ""
				if qSuccess {
					if qType, _ := res["type"].(string); qType == "select" {
						if rowsVal, ok := res["rows"].([]map[string]interface{}); ok {
							qMsg = fmt.Sprintf("SUCCESS: %d rows retrieved", len(rowsVal))
						} else {
							qMsg = "SUCCESS"
						}
					} else {
						qMsg = fmt.Sprintf("SUCCESS: %v rows affected", res["affected_rows"])
					}
				} else {
					qMsg = fmt.Sprintf("ERROR: %v", res["error"])
				}

				saveQueryHistory(ctx, qText, qDuration, qSuccess, qMsg)
			}
		}(c.Copy(), results)

		if !aborted {
			if err := tx.Commit(); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": "Failed to commit transaction"})
				return
			}
			c.JSON(http.StatusOK, gin.H{"success": true, "results": results, "logs": logs})
		} else {
			c.JSON(http.StatusOK, gin.H{"success": false, "message": "Transaction aborted due to query error", "results": results, "logs": logs})
		}
	})

	r.GET("/api/users", func(c *gin.Context) {
		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		rows, err := db.Query("SELECT User, Host FROM mysql.user ORDER BY User, Host;")
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		type UserItem struct {
			User string `json:"user"`
			Host string `json:"host"`
		}
		var list []UserItem = []UserItem{}
		for rows.Next() {
			var item UserItem
			if err := rows.Scan(&item.User, &item.Host); err == nil {
				list = append(list, item)
			}
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "users": list})
	})

	r.GET("/api/users/detail", func(c *gin.Context) {
		username := c.Query("user")
		host := c.Query("host")
		if username == "" || host == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "user and host query parameters are required"})
			return
		}

		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		var superPriv string
		err = db.QueryRow("SELECT Super_priv FROM mysql.user WHERE User = ? AND Host = ?;", username, host).Scan(&superPriv)
		isSuperuser := (err == nil && superPriv == "Y")

		rows, err := db.Query(`SELECT Db, Select_priv, Insert_priv, Update_priv, Delete_priv, Create_priv, Drop_priv 
			FROM mysql.db WHERE User = ? AND Host = ?;`, username, host)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		type GrantDetail struct {
			Db         string   `json:"db"`
			Privileges []string `json:"privileges"`
		}
		var grants []GrantDetail = []GrantDetail{}
		for rows.Next() {
			var dbName, sel, ins, upd, del, cre, drp string
			if err := rows.Scan(&dbName, &sel, &ins, &upd, &del, &cre, &drp); err == nil {
				var privs []string
				if sel == "Y" {
					privs = append(privs, "SELECT")
				}
				if ins == "Y" {
					privs = append(privs, "INSERT")
				}
				if upd == "Y" {
					privs = append(privs, "UPDATE")
				}
				if del == "Y" {
					privs = append(privs, "DELETE")
				}
				if cre == "Y" {
					privs = append(privs, "CREATE")
				}
				if drp == "Y" {
					privs = append(privs, "DROP")
				}
				grants = append(grants, GrantDetail{Db: dbName, Privileges: privs})
			}
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "superuser": isSuperuser, "grants": grants})
	})

	r.POST("/api/users/create", func(c *gin.Context) {
		var req struct {
			Username  string `json:"username"`
			Password  string `json:"password"`
			Host      string `json:"host"`
			Superuser bool   `json:"superuser"`
			Grants    []struct {
				Db         string   `json:"db"`
				Privileges []string `json:"privileges"`
			} `json:"grants"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}
		if req.Username == "" || req.Host == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "username and host are required"})
			return
		}

		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		createUserSQL := fmt.Sprintf("CREATE USER %s@%s IDENTIFIED BY %s;",
			quoteIdentifier(req.Username), quoteIdentifier(req.Host), quoteIdentifier(req.Password))

		_, err = db.Exec(createUserSQL)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to create user: %v", err)})
			return
		}

		if req.Superuser {
			grantSQL := fmt.Sprintf("GRANT ALL PRIVILEGES ON *.* TO %s@%s WITH GRANT OPTION;",
				quoteIdentifier(req.Username), quoteIdentifier(req.Host))
			_, err = db.Exec(grantSQL)
			if err != nil {
				_, _ = db.Exec(fmt.Sprintf("DROP USER %s@%s;", quoteIdentifier(req.Username), quoteIdentifier(req.Host)))
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to grant superuser privileges: %v", err)})
				return
			}
		} else {
			for _, grant := range req.Grants {
				if len(grant.Privileges) == 0 {
					continue
				}
				privString := strings.Join(grant.Privileges, ", ")
				grantSQL := fmt.Sprintf("GRANT %s ON `%s`.* TO %s@%s;",
					privString, grant.Db, quoteIdentifier(req.Username), quoteIdentifier(req.Host))
				_, err = db.Exec(grantSQL)
				if err != nil {
					_, _ = db.Exec(fmt.Sprintf("DROP USER %s@%s;", quoteIdentifier(req.Username), quoteIdentifier(req.Host)))
					c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to grant privileges: %v", err)})
					return
				}
			}
		}

		_, _ = db.Exec("FLUSH PRIVILEGES;")
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "User created successfully"})
	})

	r.POST("/api/users/delete", func(c *gin.Context) {
		var req struct {
			Username string `json:"username"`
			Host     string `json:"host"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}
		if req.Username == "" || req.Host == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "username and host are required"})
			return
		}

		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		dropSQL := fmt.Sprintf("DROP USER %s@%s;", quoteIdentifier(req.Username), quoteIdentifier(req.Host))
		_, err = db.Exec(dropSQL)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to drop user: %v", err)})
			return
		}

		_, _ = db.Exec("FLUSH PRIVILEGES;")
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "User deleted successfully"})
	})

	r.POST("/api/users/update", func(c *gin.Context) {
		var req struct {
			Username  string `json:"username"`
			Host      string `json:"host"`
			NewHost   string `json:"new_host"`
			Password  string `json:"password"`
			Superuser bool   `json:"superuser"`
			Grants    []struct {
				Db         string   `json:"db"`
				Privileges []string `json:"privileges"`
			} `json:"grants"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}
		if req.Username == "" || req.Host == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "username and host are required"})
			return
		}

		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		activeHost := req.Host

		if req.NewHost != "" && req.NewHost != req.Host {
			renameSQL := fmt.Sprintf("RENAME USER %s@%s TO %s@%s;",
				quoteIdentifier(req.Username), quoteIdentifier(req.Host),
				quoteIdentifier(req.Username), quoteIdentifier(req.NewHost))
			_, err = db.Exec(renameSQL)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to rename user host: %v", err)})
				return
			}
			activeHost = req.NewHost
		}

		if req.Password != "" {
			alterSQL := fmt.Sprintf("ALTER USER %s@%s IDENTIFIED BY %s;",
				quoteIdentifier(req.Username), quoteIdentifier(activeHost), quoteIdentifier(req.Password))
			_, err = db.Exec(alterSQL)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to update password: %v", err)})
				return
			}
		}

		revokeSQL := fmt.Sprintf("REVOKE ALL PRIVILEGES, GRANT OPTION FROM %s@%s;", quoteIdentifier(req.Username), quoteIdentifier(activeHost))
		_, _ = db.Exec(revokeSQL)

		deleteSQL := "DELETE FROM mysql.db WHERE User = ? AND Host = ?;"
		_, err = db.Exec(deleteSQL, req.Username, activeHost)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to clear old privileges: %v", err)})
			return
		}

		if req.Superuser {
			grantSQL := fmt.Sprintf("GRANT ALL PRIVILEGES ON *.* TO %s@%s WITH GRANT OPTION;",
				quoteIdentifier(req.Username), quoteIdentifier(activeHost))
			_, err = db.Exec(grantSQL)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to grant superuser privileges: %v", err)})
				return
			}
		} else {
			for _, grant := range req.Grants {
				if len(grant.Privileges) == 0 {
					continue
				}
				privString := strings.Join(grant.Privileges, ", ")
				grantSQL := fmt.Sprintf("GRANT %s ON `%s`.* TO %s@%s;",
					privString, grant.Db, quoteIdentifier(req.Username), quoteIdentifier(activeHost))
				_, err = db.Exec(grantSQL)
				if err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to grant new privileges: %v", err)})
					return
				}
			}
		}

		_, _ = db.Exec("FLUSH PRIVILEGES;")
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "User updated successfully"})
	})

	r.POST("/api/update-row", func(c *gin.Context) {
		var req struct {
			Database      string                 `json:"database"`
			Table         string                 `json:"table"`
			PkValues      map[string]interface{} `json:"pk_values"`
			UpdatedValues map[string]interface{} `json:"updated_values"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		if req.Database == "" || req.Table == "" || len(req.PkValues) == 0 || len(req.UpdatedValues) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "database, table, pk_values, and updated_values are required"})
			return
		}

		db, err := getDBConnection(c, req.Database)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		var setClauses []string
		var whereClauses []string
		var params []interface{}

		for k, v := range req.UpdatedValues {
			setClauses = append(setClauses, fmt.Sprintf("`%s` = ?", k))
			params = append(params, v)
		}

		for k, v := range req.PkValues {
			whereClauses = append(whereClauses, fmt.Sprintf("`%s` = ?", k))
			params = append(params, v)
		}

		query := fmt.Sprintf("UPDATE `%s` SET %s WHERE %s;", req.Table, strings.Join(setClauses, ", "), strings.Join(whereClauses, " AND "))

		_, err = db.Exec(query, params...)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"message": fmt.Sprintf("Updated row in `%s` successfully.", req.Table),
			"query":   query,
		})
	})

	r.POST("/api/insert-row", func(c *gin.Context) {
		var req struct {
			Database string                 `json:"database"`
			Table    string                 `json:"table"`
			Values   map[string]interface{} `json:"values"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		if req.Database == "" || req.Table == "" || len(req.Values) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "database, table, and values are required"})
			return
		}

		db, err := getDBConnection(c, req.Database)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		var cols []string
		var placeholders []string
		var params []interface{}

		for k, v := range req.Values {
			cols = append(cols, fmt.Sprintf("`%s`", k))
			placeholders = append(placeholders, "?")
			params = append(params, v)
		}

		query := fmt.Sprintf("INSERT INTO `%s` (%s) VALUES (%s);", req.Table, strings.Join(cols, ", "), strings.Join(placeholders, ", "))

		_, err = db.Exec(query, params...)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"message": fmt.Sprintf("Inserted row into `%s` successfully.", req.Table),
			"query":   query,
		})
	})

	r.POST("/api/execute-changes", func(c *gin.Context) {
		var req struct {
			Database string                   `json:"database"`
			Table    string                   `json:"table"`
			Changes  []map[string]interface{} `json:"changes"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		if req.Database == "" || len(req.Changes) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "database and changes list are required"})
			return
		}

		db, err := getDBConnection(c, req.Database)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		var queries []string

		for _, change := range req.Changes {
			action, _ := change["action"].(string)

			switch action {
			case "add_column":
				col, _ := change["column"].(map[string]interface{})
				colDef := compileColumnDef(col)
				queries = append(queries, fmt.Sprintf("ALTER TABLE `%s` ADD COLUMN %s;", req.Table, colDef))

			case "modify_column":
				oldName, _ := change["old_name"].(string)
				col, _ := change["column"].(map[string]interface{})
				colDef := compileColumnDef(col)
				newName, _ := col["field_name"].(string)
				if oldName != newName {
					queries = append(queries, fmt.Sprintf("ALTER TABLE `%s` CHANGE COLUMN `%s` %s;", req.Table, oldName, colDef))
				} else {
					queries = append(queries, fmt.Sprintf("ALTER TABLE `%s` MODIFY COLUMN %s;", req.Table, colDef))
				}

			case "drop_column":
				fieldName, _ := change["field_name"].(string)
				queries = append(queries, fmt.Sprintf("ALTER TABLE `%s` DROP COLUMN `%s`;", req.Table, fieldName))

			case "create_table":
				tblName, _ := change["table_name"].(string)
				colsVal, _ := change["columns"].([]interface{})
				var colDefs []string
				var pks []string

				for _, rawCol := range colsVal {
					col, ok := rawCol.(map[string]interface{})
					if !ok {
						continue
					}
					colDefs = append(colDefs, compileColumnDef(col))
					isPk, _ := col["is_pk"].(bool)
					if isPk {
						pks = append(pks, fmt.Sprintf("`%s`", col["field_name"].(string)))
					}
				}

				if len(pks) > 0 {
					colDefs = append(colDefs, fmt.Sprintf("PRIMARY KEY (%s)", strings.Join(pks, ", ")))
				}

				queries = append(queries, fmt.Sprintf("CREATE TABLE `%s` (\n  %s\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;", tblName, strings.Join(colDefs, ",\n  ")))

			case "drop_table":
				tblName, _ := change["table_name"].(string)
				queries = append(queries, fmt.Sprintf("DROP TABLE `%s`;", tblName))

			case "create_index":
				tblName, _ := change["table_name"].(string)
				idxName, _ := change["index_name"].(string)
				colsVal, _ := change["columns"].([]interface{})
				var colNames []string
				for _, rawCol := range colsVal {
					if colStr, ok := rawCol.(string); ok {
						colNames = append(colNames, fmt.Sprintf("`%s`", colStr))
					}
				}
				unique, _ := change["unique"].(bool)
				uniqueStr := ""
				if unique {
					uniqueStr = "UNIQUE "
				}
				queries = append(queries, fmt.Sprintf("CREATE %sINDEX `%s` ON `%s` (%s);", uniqueStr, idxName, tblName, strings.Join(colNames, ", ")))
			}
		}

		if len(queries) == 0 {
			c.JSON(http.StatusOK, gin.H{"success": true, "message": "No actions to execute", "queries": []string{}})
			return
		}

		tx, err := db.Begin()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
			return
		}

		var logs []gin.H
		aborted := false

		for _, q := range queries {
			startTime := time.Now()
			logEntry := gin.H{
				"timestamp": startTime.Format("2006-01-02 15:04:05"),
				"query":     q,
			}

			_, err = tx.Exec(q)
			duration := time.Since(startTime).Seconds()
			logEntry["duration"] = fmt.Sprintf("%.3fs", duration)

			if err != nil {
				tx.Rollback()
				logEntry["status"] = "ERROR"
				logEntry["message"] = err.Error()
				logs = append(logs, logEntry)
				aborted = true
				break
			}

			logEntry["status"] = "SUCCESS"
			logEntry["message"] = "DDL executed successfully"
			logs = append(logs, logEntry)
		}

		if aborted {
			errMessage := "DDL execution aborted"
			if len(logs) > 0 {
				lastLog := logs[len(logs)-1]
				if msg, ok := lastLog["message"].(string); ok && msg != "" {
					errMessage = fmt.Sprintf("DDL execution aborted: %s", msg)
				}
			}
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"message": errMessage,
				"queries": queries,
				"logs":    logs,
			})
			return
		}

		if err := tx.Commit(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": "Failed to commit DDL execution"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"message": "All structural changes applied successfully.",
			"queries": queries,
			"logs":    logs,
		})
	})

	r.POST("/api/batch-query", func(c *gin.Context) {
		var req struct {
			Query     string   `json:"query"`
			Databases []string `json:"databases"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		if len(req.Databases) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "databases list is empty"})
			return
		}

		var allLogs []gin.H
		queries := splitSQLQueries(req.Query)

		for _, dbName := range req.Databases {
			db, err := getDBConnection(c, dbName)
			if err != nil {
				allLogs = append(allLogs, gin.H{
					"timestamp": time.Now().Format("2006-01-02 15:04:05"),
					"database":  dbName,
					"status":    "ERROR",
					"query":     "Connect to " + dbName,
					"message":   err.Error(),
					"duration":  "0s",
				})
				continue
			}

			tx, err := db.Begin()
			if err != nil {
				allLogs = append(allLogs, gin.H{
					"timestamp": time.Now().Format("2006-01-02 15:04:05"),
					"database":  dbName,
					"status":    "ERROR",
					"query":     "Begin Transaction on " + dbName,
					"message":   err.Error(),
					"duration":  "0s",
				})
				db.Close()
				continue
			}

			dbAborted := false
			for _, q := range queries {
				q = strings.TrimSpace(q)
				if q == "" {
					continue
				}

				startTime := time.Now()
				timestamp := startTime.Format("2006-01-02 15:04:05")
				logEntry := gin.H{
					"timestamp": timestamp,
					"database":  dbName,
					"query":     q,
				}

				qUpper := strings.ToUpper(q)
				isSelect := strings.HasPrefix(qUpper, "SELECT") ||
					strings.HasPrefix(qUpper, "SHOW") ||
					strings.HasPrefix(qUpper, "DESCRIBE") ||
					strings.HasPrefix(qUpper, "EXPLAIN")

				if isSelect {
					rows, queryErr := tx.Query(q)
					duration := time.Since(startTime).Seconds()
					logEntry["duration"] = fmt.Sprintf("%.3fs", duration)

					if queryErr != nil {
						tx.Rollback()
						logEntry["status"] = "ERROR"
						logEntry["message"] = queryErr.Error()
						allLogs = append(allLogs, logEntry)
						dbAborted = true
						break
					}

					cols, _ := rows.Columns()
					scanArgs := make([]interface{}, len(cols))
					values := make([]interface{}, len(cols))
					for i := range values {
						scanArgs[i] = &values[i]
					}
					rowCount := 0
					for rows.Next() {
						_ = rows.Scan(scanArgs...)
						rowCount++
					}
					rows.Close()

					logEntry["status"] = "SUCCESS"
					logEntry["message"] = fmt.Sprintf("%d rows returned", rowCount)
					allLogs = append(allLogs, logEntry)
				} else {
					res, queryErr := tx.Exec(q)
					duration := time.Since(startTime).Seconds()
					logEntry["duration"] = fmt.Sprintf("%.3fs", duration)

					if queryErr != nil {
						tx.Rollback()
						logEntry["status"] = "ERROR"
						logEntry["message"] = queryErr.Error()
						allLogs = append(allLogs, logEntry)
						dbAborted = true
						break
					}

					affected, _ := res.RowsAffected()
					logEntry["status"] = "SUCCESS"
					logEntry["message"] = fmt.Sprintf("%d rows affected", affected)
					allLogs = append(allLogs, logEntry)
				}
			}

			if !dbAborted {
				if err := tx.Commit(); err != nil {
					allLogs = append(allLogs, gin.H{
						"timestamp": time.Now().Format("2006-01-02 15:04:05"),
						"database":  dbName,
						"status":    "ERROR",
						"query":     "Commit Transaction on " + dbName,
						"message":   err.Error(),
						"duration":  "0s",
					})
				}
			}
			db.Close()
		}

		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"logs":    allLogs,
		})
	})

	r.GET("/api/auto-backup/configs", func(c *gin.Context) {
		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		_, _ = db.Exec(`CREATE TABLE IF NOT EXISTS auto_backup (
			db_name VARCHAR(255) PRIMARY KEY,
			backup_time VARCHAR(5) NOT NULL,
			keep_days INT NOT NULL,
			is_active TINYINT DEFAULT 1
		);`)

		rows, err := db.Query("SELECT db_name, backup_time, keep_days, is_active FROM auto_backup;")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer rows.Close()

		var configs []gin.H
		for rows.Next() {
			var dbName, backupTime string
			var keepDays int
			var isActive int
			if err := rows.Scan(&dbName, &backupTime, &keepDays, &isActive); err == nil {
				configs = append(configs, gin.H{
					"db_name":     dbName,
					"backup_time": backupTime,
					"keep_days":   keepDays,
					"is_active":   isActive == 1,
				})
			}
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "configs": configs})
	})

	r.POST("/api/auto-backup/save", func(c *gin.Context) {
		var req struct {
			DbName     string `json:"db_name"`
			BackupTime string `json:"backup_time"`
			KeepDays   int    `json:"keep_days"`
			IsActive   bool   `json:"is_active"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		db, err := getDBConnection(c, "mysql")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		defer db.Close()

		isActiveVal := 0
		if req.IsActive {
			isActiveVal = 1
		}

		_, err = db.Exec(`INSERT INTO auto_backup (db_name, backup_time, keep_days, is_active) 
			VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE backup_time=?, keep_days=?, is_active=?;`,
			req.DbName, req.BackupTime, req.KeepDays, isActiveVal, req.BackupTime, req.KeepDays, isActiveVal)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "message": "Auto backup configuration saved successfully."})
	})

	r.POST("/api/backup-now", func(c *gin.Context) {
		var req struct {
			Databases     []string `json:"databases"`
			DirectoryName string   `json:"directory_name"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		if len(req.Databases) == 0 || req.DirectoryName == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "databases and directory_name are required"})
			return
		}

		creds := DbCreds{
			Host:     c.GetHeader("X-DB-Host"),
			Port:     c.GetHeader("X-DB-Port"),
			User:     c.GetHeader("X-DB-User"),
			Password: c.GetHeader("X-DB-Password"),
		}

		targetDir := filepath.Join("backup", req.DirectoryName)
		var errors []string

		for _, dbName := range req.Databases {
			err := runMysqldump(&creds, dbName, targetDir, dbName+".sql")
			if err != nil {
				errors = append(errors, err.Error())
			}
		}

		if len(errors) > 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": strings.Join(errors, "; ")})
			return
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "message": "Backup completed successfully."})
	})

	r.GET("/api/backup/directories", func(c *gin.Context) {
		_ = os.MkdirAll("backup", 0755)
		files, err := os.ReadDir("backup")
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
			return
		}

		var dirs []string
		for _, f := range files {
			if f.IsDir() {
				dirs = append(dirs, f.Name())
			}
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "directories": dirs})
	})

	r.GET("/api/backup/files", func(c *gin.Context) {
		dir := c.Query("directory")
		if dir == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "directory param is required"})
			return
		}

		dirPath := filepath.Join("backup", dir)
		files, err := os.ReadDir(dirPath)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}

		var fileInfos []gin.H
		for _, f := range files {
			if !f.IsDir() && strings.HasSuffix(f.Name(), ".sql") {
				info, err := f.Info()
				createTime := ""
				size := int64(0)
				if err == nil {
					createTime = info.ModTime().Format("2006-01-02 15:04:05")
					size = info.Size()
				}
				fileInfos = append(fileInfos, gin.H{
					"filename":    f.Name(),
					"create_time": createTime,
					"size":        size,
				})
			}
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "files": fileInfos})
	})

	r.POST("/api/backup/restore", func(c *gin.Context) {
		var req struct {
			Directory       string            `json:"directory"`
			Files           []string          `json:"files"`
			TargetDatabases map[string]string `json:"target_databases"`
			CleanRestore    bool              `json:"clean_restore"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		creds := DbCreds{
			Host:     c.GetHeader("X-DB-Host"),
			Port:     c.GetHeader("X-DB-Port"),
			User:     c.GetHeader("X-DB-User"),
			Password: c.GetHeader("X-DB-Password"),
		}

		dirPath := filepath.Join("backup", req.Directory)
		var errors []string

		for _, filename := range req.Files {
			targetDb, ok := req.TargetDatabases[filename]
			if !ok || targetDb == "" {
				errors = append(errors, fmt.Sprintf("target database for file %s is missing", filename))
				continue
			}

			// Pre-restoration backup if database exists
			checkDb, checkErr := getDBConnection(c, targetDb)
			if checkErr == nil {
				checkDb.Close()
				backupTimeStr := time.Now().Format("20060102_150405")
				tmpBackupName := fmt.Sprintf("%s.sql.%s", targetDb, backupTimeStr)
				_ = runMysqldump(&creds, targetDb, dirPath, tmpBackupName)
			}

			if req.CleanRestore {
				tempDb, err := getDBConnection(c, "")
				if err != nil {
					errors = append(errors, fmt.Sprintf("Failed to connect for recreation: %v", err))
					continue
				}
				_, _ = tempDb.Exec(fmt.Sprintf("DROP DATABASE IF EXISTS `%s`;", targetDb))
				_, err = tempDb.Exec(fmt.Sprintf("CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;", targetDb))
				tempDb.Close()
				if err != nil {
					errors = append(errors, fmt.Sprintf("Failed to recreate database `%s`: %v", targetDb, err))
					continue
				}
			} else {
				tempDb, err := getDBConnection(c, "")
				if err == nil {
					_, _ = tempDb.Exec(fmt.Sprintf("CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;", targetDb))
					tempDb.Close()
				}
			}

			sqlFilePath := filepath.Join(dirPath, filename)
			restoreErr := runMysqlRestore(&creds, targetDb, sqlFilePath)
			if restoreErr != nil {
				errors = append(errors, fmt.Sprintf("Restore of %s to %s failed: %v", filename, targetDb, restoreErr))
			}
		}

		if len(errors) > 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": strings.Join(errors, "; ")})
			return
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "message": "Restoration completed successfully."})
	})

	r.POST("/api/db-copy", func(c *gin.Context) {
		var req struct {
			SourceDatabases []string `json:"source_databases"`
			TargetDatabase  string   `json:"target_database"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid JSON request"})
			return
		}

		if len(req.SourceDatabases) == 0 || req.TargetDatabase == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "source_databases and target_database are required"})
			return
		}

		creds := DbCreds{
			Host:     c.GetHeader("X-DB-Host"),
			Port:     c.GetHeader("X-DB-Port"),
			User:     c.GetHeader("X-DB-User"),
			Password: c.GetHeader("X-DB-Password"),
		}

		copyBackupDir := filepath.Join("backup", "copy_backup")
		_ = os.MkdirAll(copyBackupDir, 0755)

		targetCheck, checkErr := getDBConnection(c, req.TargetDatabase)
		if checkErr == nil {
			targetCheck.Close()
			backupTimeStr := time.Now().Format("20060102_150405")
			backupFilename := fmt.Sprintf("%s.sql.%s", req.TargetDatabase, backupTimeStr)
			_ = runMysqldump(&creds, req.TargetDatabase, copyBackupDir, backupFilename)
		}

		tempDb, err := getDBConnection(c, "")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
			return
		}
		_, _ = tempDb.Exec(fmt.Sprintf("DROP DATABASE IF EXISTS `%s`;", req.TargetDatabase))
		_, err = tempDb.Exec(fmt.Sprintf("CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;", req.TargetDatabase))
		tempDb.Close()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": fmt.Sprintf("Failed to create target database: %v", err)})
			return
		}

		var copyErrors []string
		tempSqlFile := filepath.Join(os.TempDir(), fmt.Sprintf("temp_copy_%d.sql", time.Now().UnixNano()))

		for _, srcDb := range req.SourceDatabases {
			err := runMysqldump(&creds, srcDb, os.TempDir(), filepath.Base(tempSqlFile))
			if err != nil {
				copyErrors = append(copyErrors, fmt.Sprintf("Dump source %s failed: %v", srcDb, err))
				continue
			}

			restoreErr := runMysqlRestore(&creds, req.TargetDatabase, tempSqlFile)
			_ = os.Remove(tempSqlFile)
			if restoreErr != nil {
				copyErrors = append(copyErrors, fmt.Sprintf("Restore to %s failed: %v", req.TargetDatabase, restoreErr))
				break
			}
		}

		if len(copyErrors) > 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": strings.Join(copyErrors, "; ")})
			return
		}

		c.JSON(http.StatusOK, gin.H{"success": true, "message": "Database copied successfully."})
	})

	// Start Gin Server
	r.Run(fmt.Sprintf(":%d", *portPtr))
}
