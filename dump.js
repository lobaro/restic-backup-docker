const MongoClient = require('mongodb').MongoClient;
const mysql = require('mysql2');
const { Pool } = require('pg');
const { copyToStream } = require('pg-copy-streams');

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const moment = require('moment');
const util = require('util');


/**
 * 导出所有MongoDB数据库的数据
 * 
 * 此函数会连接MongoDB服务器，获取所有非系统数据库，
 * 并将每个数据库中的所有集合数据导出为JSON文件。
 * 
 * 环境变量要求:
 * - MONGO_ROOT_USERNAME: MongoDB用户名
 * - MONGO_ROOT_PASSWORD: MongoDB密码 
 * - MONGO_HOST: MongoDB主机地址
 * - MONGO_PORT: MongoDB端口号
 * - MONGO_DATABASE: MongoDB数据库名称
 * 
 * 导出文件将保存在 ./dump 目录下,按数据库名和集合名组织:
 * ./dump/
 *   ├── database1/
 *   │   ├── collection1.json
 *   │   └── collection2.json
 *   └── database2/
 *       └── collection1.json
 * 
 * @async
 * @throws {Error} 当数据库连接失败或导出过程出错时抛出异常
 */
async function dumpMongoAllDatabases() {
  const uri = `mongodb://${process.env.DATABASE_USER || process.env.MONGO_ROOT_USERNAME}:${process.env.DATABASE_PASSWORD || process.env.MONGO_ROOT_PASSWORD}@${process.env.DATABASE_HOST || process.env.MONGO_HOST}:${process.env.DATABASE_PORT || process.env.MONGO_PORT || '27017'}/`;
  // const dbName = process.env.DATABASE_NAME || process.env.MONGO_DATEBASE; // 替换成你的数据库名称
  try {
    const client = new MongoClient(uri, { useNewUrlParser: true, useUnifiedTopology: true });
    await client.connect();

    // 获取所有数据库名称
    const databases = await client.db().admin().listDatabases();
    const databaseNames = databases.databases.map(db => db.name);

    // 创建一个文件夹来存储 dump 文件
    const dumpDir = './dump';
    if (!fs.existsSync(dumpDir)) {
      fs.mkdirSync(dumpDir);
    }

    // 循环遍历每个数据库并 dump
    for (const dbName of databaseNames) {
      // 判断数据库是否为系统数据库
      if (dbName === 'admin' || dbName === 'local' || dbName === 'config') {
        console.log(`Skipping system database: ${dbName}`);
        continue;
      }
      const db = client.db(dbName);

      // 获取所有集合
      const collections = await db.collections();

      // 循环遍历每个集合并 dump
      for (const collection of collections) {
        const collectionName = collection.collectionName;

        // 创建一文件来存储 dump 数据
        const dumpFile = `${dumpDir}/${dbName}/${collectionName}.json`;

        // 创建文件夹
        const collectionDir = `${dumpDir}/${dbName}`;
        if (!fs.existsSync(collectionDir)) {
          fs.mkdirSync(collectionDir);
        }

        // 读取集合数据
        const documents = await collection.find().toArray();

        // 将数据写入文件
        fs.writeFileSync(dumpFile, JSON.stringify(documents, null, 2));

        console.log(`Dumped ${collectionName} to ${dumpFile}`);
      }

      console.log(`Database ${dbName} dump completed!`);
    }

    console.log('All databases dump completed!');
    await client.close();
  } catch (err) {
    console.error('Error during database dump:', err);
  }
}

/**
 * MongoDB数据库备份工具函数
 * 
 * @description 该函数用于备份MongoDB数据库中的所有集合数据
 * 将每个集合的数据以JSON格式保存到本地文件中
 * 
 * @param {string} uri - MongoDB连接字符串
 * @param {string[]} databaseNames - 需要备份的数据库名称列表
 * 
 * @example
 * const uri = 'mongodb://localhost:27017';
 * const databaseNames = ['mydb1', 'mydb2'];
 * await dumpMongoDatabases(uri, databaseNames);
 * 
 * @returns {Promise<void>}
 * @throws {Error} 当数据库连接或备份过程出错时抛出异常
 */
async function dumpMongoDatabase() {
  const uri = `mongodb://${process.env.DATABASE_USER || process.env.MONGO_ROOT_USERNAME}:${process.env.DATABASE_PASSWORD || process.env.MONGO_ROOT_PASSWORD}@${process.env.DATABASE_HOST || process.env.MONGO_HOST}:${process.env.DATABASE_PORT || process.env.MONGO_PORT || '27017'}/`;
  const dbName = process.env.DATABASE_NAME || process.env.MONGO_DATABASE; // 替换成你的数据库名称
  try {
    if(!dbName){
      console.error('DATABASE_NAME or MONGO_DATEBASE is not set');
      return;
    }
    const client = new MongoClient(uri, { useNewUrlParser: true, useUnifiedTopology: true });
    await client.connect();
    const db = client.db(dbName);

    const collections = await db.collections();

    // 创建一个文件夹来存储 dump 文件
    const dumpDir = './dump';
    if (!fs.existsSync(dumpDir)) {
      fs.mkdirSync(dumpDir);
    }

    // 循环遍历每个集合并 dump
    for (const collection of collections) {
      const collectionName = collection.collectionName;

      // 创建一个文件来存储 dump 数据
      const dumpFile = `${dumpDir}/${collectionName}.json`;

      // 读取集合数据
      const documents = await collection.find().toArray();

      // 将数据写入文件
      fs.writeFileSync(dumpFile, JSON.stringify(documents, null, 2));

      console.log(`Dumped ${collectionName} to ${dumpFile}`);
    }

    console.log('Database dump completed!');
    await client.close();
  } catch (err) {
    console.error('Error during database dump:', err);
  }
}


/**
 * 备份MySQL数据库中的指定表数据到本地文件
 * 
 * @param {Object} config - MySQL数据库连接配置
 * @param {string} config.host - 数据库主机地址
 * @param {string} config.user - 数据库用户名
 * @param {string} config.password - 数据库密码
 * @param {string} config.database - 数据库名称
 * @param {string} backupDir - 备份文件保存目录
 * 
 * @example
 * const config = {
 *   host: 'localhost',
 *   user: 'root', 
 *   password: '123456',
 *   database: 'mydb'
 * };
 * const backupDir = './backup';
 * await backupMysqlDatabase(config, backupDir);
 * 
 * @returns {Promise<void>}
 * @throws {Error} 当数据库连接或备份过程出错时抛出异常
 */
async function backupMysqlAllDatabase() {
  const config = {
    host: process.env.DATABASE_HOST || process.env.MYSQL_HOST,
    user: process.env.DATABASE_USER || process.env.MYSQL_USER,
    password: process.env.DATABASE_PASSWORD || process.env.MYSQL_PASSWORD,
    database: process.env.DATABASE_NAME || process.env.MYSQL_DATABASE,
    port: parseInt(process.env.DATABASE_PORT || process.env.MYSQL_PORT || 3306)
  };
  const connection = mysql.createConnection(config).promise();
  const backupDir = './dump';

  try {
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }

    await connection.connect();
    
    // 获取所有表名
    const [tables] = await connection.query(`
      SELECT TABLE_NAME 
      FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_SCHEMA = ? 
      AND TABLE_NAME NOT LIKE 'sys_%'
      AND TABLE_NAME NOT LIKE 'performance_%'
      AND TABLE_NAME NOT LIKE 'innodb_%'
    `, [config.database]);

    const timestamp = moment().format('YYYYMMDDHHmmss');
    const backupFile = path.join(backupDir, `mysql-backup-${timestamp}.sql`);
    const writeStream = fs.createWriteStream(backupFile);
    
    // 写入文件头部信息
    writeStream.write(`-- MySQL dump\n`);
    writeStream.write(`-- Created at: ${moment().format('YYYY-MM-DD HH:mm:ss')}\n\n`);
    writeStream.write(`SET FOREIGN_KEY_CHECKS=0;\n\n`);

    // 为每个表创建备份
    for (const table of tables) {
      const tableName = table.TABLE_NAME;
      
      // 获取表结构
      const [tableStructure] = await connection.query(`SHOW CREATE TABLE \`${tableName}\``);
      writeStream.write(`-- Table structure: ${tableName}\n`);
      writeStream.write(`DROP TABLE IF EXISTS \`${tableName}\`;\n`);
      writeStream.write(`${tableStructure[0]['Create Table']};\n\n`);

      // 获取表数据
      const [rows] = await connection.query(`SELECT * FROM \`${tableName}\``);
      
      if (rows.length > 0) {
        writeStream.write(`-- Table data: ${tableName}\n`);
        const columns = Object.keys(rows[0]);
        
        for (const row of rows) {
          const values = columns.map(column => {
            const value = row[column];
            if (value === null) return 'NULL';
            if (typeof value === 'number') return value;
            return `'${value.toString().replace(/'/g, "''")}'`;
          });
          
          writeStream.write(
            `INSERT INTO \`${tableName}\` (${columns.map(c => '`'+c+'`').join(', ')}) ` +
            `VALUES (${values.join(', ')});\n`
          );
        }
        writeStream.write('\n');
      }
    }

    writeStream.write(`SET FOREIGN_KEY_CHECKS=1;\n`);
    writeStream.end();
    console.log(`Database backup completed! Backup file: ${backupFile}`);

  } catch (err) {
    console.error('Error during database backup:', err);
  } finally {
    if (connection) {
      await connection.end();
    }
  }
}

/**
 * 备份MySQL数据库中的指定表数据���本地文件
 * 
 * @param {Object} config - MySQL数据库连接配置
 * @param {string} config.host - 数据库主机地址
 * @param {string} config.user - 数据库用户名
 * @param {string} config.password - 数据库密码
 * @param {string} config.database - 数据库名称
 * @param {string} backupDir - 备份文件保存目录
 * 
 * @example
 * const config = {
 *   host: 'localhost',
 *   user: 'root', 
 *   password: '123456',
 *   database: 'mydb'
 * };
 * const backupDir = './backup';
 * await backupMysqlDatabase(config, backupDir);
 * 
 * @returns {Promise<void>}
 * @throws {Error} 当数据库连接或备份过程出错时抛出异常
 */
async function backupMysqlDatabase() {
  const config = {
    host: process.env.DATABASE_HOST || process.env.MYSQL_HOST,
    user: process.env.DATABASE_USER || process.env.MYSQL_USER,
    password: process.env.DATABASE_PASSWORD || process.env.MYSQL_PASSWORD,
    database: process.env.DATABASE_NAME || process.env.MYSQL_DATABASE,
    port: parseInt(process.env.DATABASE_PORT || process.env.MYSQL_PORT || 3306)
  };
  const connection = mysql.createConnection(config).promise();
  const backupDir = './dump';

  try {
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }

    await connection.connect();
    
    // 获取数据库中的所有表
    const [tables] = await connection.query(`
      SELECT TABLE_NAME 
      FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_SCHEMA = ?
    `, [config.database]);
    
    const timestamp = moment().format('YYYYMMDDHHmmss');
    const backupFile = path.join(backupDir, `backup-${timestamp}.sql`);
    const writeStream = fs.createWriteStream(backupFile);

    // 遍历每个表并备份
    for (const table of tables) {
      const tableName = table.TABLE_NAME;
      
      // 获取表结构
      const [tableStructure] = await connection.query(`SHOW CREATE TABLE \`${tableName}\``);
      
      // 写入表结构
      writeStream.write(`-- Table structure for ${tableName}\n`);
      writeStream.write(`DROP TABLE IF EXISTS \`${tableName}\`;\n`);
      writeStream.write(`${tableStructure[0]['Create Table']};\n\n`);
      
      // 获取表数据
      const [rows] = await connection.query(`SELECT * FROM \`${tableName}\``);
      
      if (rows.length > 0) {
        writeStream.write(`-- Data for table ${tableName}\n`);
        const columns = Object.keys(rows[0]);
        
        for (const row of rows) {
          const values = columns.map(column => {
            const value = row[column];
            if (value === null) return 'NULL';
            if (typeof value === 'number') return value;
            return `'${value.toString().replace(/'/g, "''")}'`;
          });
          
          writeStream.write(
            `INSERT INTO \`${tableName}\` (${columns.map(c => '`'+c+'`').join(', ')}) ` +
            `VALUES (${values.join(', ')});\n`
          );
        }
        writeStream.write('\n');
      }
    }

    writeStream.end();
    console.log(`Database backup completed! Backup file: ${backupFile}`);

  } catch (err) {
    console.error('Error during database backup:', err);
  } finally {
    if (connection) {
      await connection.end();
    }
  }
}


/**
 * 备份PostgreSQL数据库中的所有表数据到本地文件
 * 
 * @param {Object} config - PostgreSQL数据库连接配置
 * @param {string} config.user - 数据库用户名
 * @param {string} config.host - 数据库主机地址
 * @param {string} config.database - 数据库名称
 * @param {string} config.password - 数据库密码
 * @param {number} config.port - 数据库端口号
 * @param {string} backupDir - 备份文件保存目录
 */
async function backupPostgresAllDatabase() {
  const config = {
    host: process.env.DATABASE_HOST || process.env.PG_HOST,
    user: process.env.DATABASE_USER || process.env.PG_USER,
    password: process.env.DATABASE_PASSWORD || process.env.PG_PASSWORD,
    database: process.env.DATABASE_NAME || process.env.PG_DATABASE,
    port: parseInt(process.env.DATABASE_PORT || process.env.PG_PORT || 5432),
  };
  const pool = new Pool(config);
  const backupDir = './dump';

  try {
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }
    
    const timestamp = moment().format('YYYYMMDDHHmmss');
    const backupFile = path.join(backupDir, `postgres-backup-${timestamp}.sql`);
    const writeStream = fs.createWriteStream(backupFile);

    // 写入文件头部信息
    writeStream.write(`-- PostgreSQL dump\n`);
    writeStream.write(`-- Created at: ${moment().format('YYYY-MM-DD HH:mm:ss')}\n\n`);

    // 获取所有表名
    const { rows: tables } = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
      AND table_name NOT LIKE 'pg_%'
      AND table_name NOT LIKE 'sql_%'
    `);

    for (const table of tables) {
      const tableName = table.table_name;
      
      // 获取表结构
      const { rows: columns } = await pool.query(`
        SELECT column_name, data_type, character_maximum_length, 
               is_nullable, column_default
        FROM information_schema.columns 
        WHERE table_name = $1 
        ORDER BY ordinal_position
      `, [tableName]);

      // 写入表结构
      writeStream.write(`-- Table structure: ${tableName}\n`);
      writeStream.write(`DROP TABLE IF EXISTS "${tableName}";\n`);
      writeStream.write(`CREATE TABLE "${tableName}" (\n`);
      
      const columnDefs = columns.map(col => {
        let def = `  "${col.column_name}" ${col.data_type}`;
        if (col.character_maximum_length) {
          def += `(${col.character_maximum_length})`;
        }
        if (col.is_nullable === 'NO') {
          def += ' NOT NULL';
        }
        if (col.column_default) {
          def += ` DEFAULT ${col.column_default}`;
        }
        return def;
      });
      
      writeStream.write(columnDefs.join(',\n'));
      writeStream.write('\n);\n\n');

      // 获取并写入表数据
      const { rows: data } = await pool.query(`SELECT * FROM "${tableName}"`);
      if (data.length > 0) {
        writeStream.write(`-- Table data: ${tableName}\n`);
        for (const row of data) {
          const values = Object.values(row).map(val => {
            if (val === null) return 'NULL';
            if (typeof val === 'number') return val;
            return `'${val.toString().replace(/'/g, "''")}'`;
          });
          
          writeStream.write(
            `INSERT INTO "${tableName}" (${Object.keys(row).map(k => `"${k}"`).join(', ')}) ` +
            `VALUES (${values.join(', ')});\n`
          );
        }
        writeStream.write('\n');
      }
    }

    writeStream.end();
    console.log(`Database backup completed! Backup file: ${backupFile}`);

  } catch (err) {
    console.error('Error during database backup:', err);
  } finally {
    if (pool) {
      await pool.end();
    }
  }
}

/**
 * 备份PostgreSQL数据库中的指定的表数据到本地文件
 * 
 * @param {Object} config - PostgreSQL数据库连接配置
 * @param {string} config.user - 数据库用户名
 * @param {string} config.host - 数据库主机地址
 * @param {string} config.database - 数据库名称
 * @param {string} config.password - 数据库密码
 * @param {number} config.port - 数据库端口号
 * @param {string} backupDir - 备份文件保存目录
 */
async function backupPostgresDatabase() {
  const config = {
    host: process.env.DATABASE_HOST || process.env.PG_HOST,
    user: process.env.DATABASE_USER || process.env.PG_USER,
    password: process.env.DATABASE_PASSWORD || process.env.PG_PASSWORD,
    database: process.env.DATABASE_NAME || process.env.PG_DATABASE,
    port: parseInt(process.env.DATABASE_PORT || process.env.PG_PORT || 5432),
  };
  const pool = new Pool(config);
  const backupDir = './dump';
  const tableName = process.env.TABLE_NAME; // 新增：从环境变量获取表名

  try {
    if (!tableName) {
      throw new Error('TABLE_NAME environment variable is not set');
    }

    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }
    
    await pool.connect();
    const timestamp = moment().format('YYYYMMDDHHmmss');
    const backupFile = path.join(backupDir, `${tableName}-${timestamp}.sql`);
    const writeStream = fs.createWriteStream(backupFile);

    // 写入文件头部信息
    writeStream.write(`-- PostgreSQL dump of table ${tableName}\n`);
    writeStream.write(`-- Created at: ${moment().format('YYYY-MM-DD HH:mm:ss')}\n\n`);

    // 获取表结构
    const { rows: columns } = await pool.query(`
      SELECT column_name, data_type, character_maximum_length, 
             is_nullable, column_default
      FROM information_schema.columns 
      WHERE table_name = $1 
      ORDER BY ordinal_position
    `, [tableName]);

    // 写入表结构
    writeStream.write(`-- Table structure\n`);
    writeStream.write(`DROP TABLE IF EXISTS "${tableName}";\n`);
    writeStream.write(`CREATE TABLE "${tableName}" (\n`);
    
    const columnDefs = columns.map(col => {
      let def = `  "${col.column_name}" ${col.data_type}`;
      if (col.character_maximum_length) {
        def += `(${col.character_maximum_length})`;
      }
      if (col.is_nullable === 'NO') {
        def += ' NOT NULL';
      }
      if (col.column_default) {
        def += ` DEFAULT ${col.column_default}`;
      }
      return def;
    });
    
    writeStream.write(columnDefs.join(',\n'));
    writeStream.write('\n);\n\n');

    // 获取并写入表数据
    const { rows: data } = await pool.query(`SELECT * FROM "${tableName}"`);
    if (data.length > 0) {
      writeStream.write(`-- Table data\n`);
      for (const row of data) {
        const values = Object.values(row).map(val => {
          if (val === null) return 'NULL';
          if (typeof val === 'number') return val;
          return `'${val.toString().replace(/'/g, "''")}'`;
        });
        
        writeStream.write(
          `INSERT INTO "${tableName}" (${Object.keys(row).map(k => `"${k}"`).join(', ')}) ` +
          `VALUES (${values.join(', ')});\n`
        );
      }
    }

    writeStream.end();
    console.log(`Table ${tableName} has been backed up to ${backupFile}`);
    console.log('Database backup completed!');

  } catch (err) {
    console.error('Error during database backup:', err);
  } finally {
    if (pool) {
      await pool.end();
    }
  }
}

// 创建一个主函数来处理数据库备份
async function main() {
  // 通过TIME_RANGE环境变量指定时间范围，格式为"HH-HH"，如"0-23"
  const timeRange = process.env.DATABASE_BACKUP_TIME || "0-23";
  const [startStr, endStr] = timeRange.split("-");
  let start = parseInt(startStr);
  let end = parseInt(endStr);
  const now = moment().hour();
  // 验证时间范围的有效性
  if (isNaN(start) || isNaN(end) || start < 0 || start > 23 || end < 0 || end > 23) {
    console.error('Invalid time range format, using default value "0-23"');
    // return;
    start = 0;
    end = 23;
  }
  console.log(`Current time: ${now}, Specified time range: ${start}-${end}`);
  if (now < start || now > end) {
    console.log(`Now not within the specified time period ${process.env.DATABASE_BACKUP_TIME}, Database Dump Task has been cancelled.`);
    return;
  }
  // 根据 DATABASE_TYPE 全局变判断要执行的备份类型
  if(process.env.DATABASE_TYPE){
    let type = process.env.DATABASE_TYPE.toLowerCase()
    switch(type){
      case "mongo":
      case "mongodb":
        if(process.env.DATABASE_NAME){
          await dumpMongoDatabase()
        }else{
          await dumpMongoAllDatabases()
        }
        break;
      case "mysql":
        if(process.env.DATABASE_NAME){
          await backupMysqlDatabase()
        }else{
          await backupMysqlAllDatabase()
        }
        break;
      case "pg":
      case "postgres":
      case "postgresql":
        if(process.env.TABLE_NAME){
          await backupPostgresDatabase()
        }else{
          await backupPostgresAllDatabase()
        }
        break;
      default:
        console.error('不支持的数据库类型:', type);
        break;
    }
  }
}

// 执行主函数
main().catch(console.error);
