const MongoClient = require('mongodb').MongoClient;
const mysql = require('mysql');
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

      // 将数���写入文件
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
  const connection = mysql.createConnection(config);
  const backupDir = './dump';

  try {
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }

    await connection.connect();
    
    // 获取所有表名
    const [tables] = await util.promisify(connection.query)
      .call(connection, `
        SELECT TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_SCHEMA = ? 
        AND TABLE_NAME NOT LIKE 'sys_%'
        AND TABLE_NAME NOT LIKE 'performance_%'
        AND TABLE_NAME NOT LIKE 'innodb_%'
      `, [config.database]);

    const timestamp = moment().format('YYYYMMDDHHmmss');
    
    // 为每个表创建备份
    for (const table of tables) {
      const tableName = table.TABLE_NAME;
      const tableBackupFile = path.join(backupDir, `${tableName}-${timestamp}.csv`);
      
      const writeStream = fs.createWriteStream(tableBackupFile);
      const query = `SELECT * FROM ${tableName}`;
      const stream = connection.query(query);
      
      await new Promise((resolve, reject) => {
        stream.on('error', reject);
        stream.on('result', (row) => {
          const rowString = Object.values(row).join(',') + '\n';
          writeStream.write(rowString);
        });
        stream.on('end', () => {
          writeStream.end();
          console.log(`表 ${tableName} 已备份到 ${tableBackupFile}`);
          resolve();
        });
      });
    }

    console.log('所有数据表备份完成！');
  } catch (err) {
    console.error('数据库备份过程中出错:', err);
  } finally {
    if (connection) {
      connection.end();
    }
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
async function backupMysqlDatabase() {
  const config = {
    host: process.env.DATABASE_HOST || process.env.MYSQL_HOST,
    user: process.env.DATABASE_USER || process.env.MYSQL_USER,
    password: process.env.DATABASE_PASSWORD || process.env.MYSQL_PASSWORD,
    database: process.env.DATABASE_NAME || process.env.MYSQL_DATABASE,
    port: parseInt(process.env.DATABASE_PORT || process.env.MYSQL_PORT || 3306)
  };
  const connection = mysql.createConnection(config);
  const backupDir = './dump';

  try {
    // 创建备份目录
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }

    // 连接数据库
    await connection.connect();

    // 获取当前时间作为备份文件名
    const timestamp = moment().format('YYYYMMDDHHmmss');
    const backupFile = path.join(backupDir, `backup-${timestamp}.sql`);

    // 执行备份命令
    const query = `SELECT * FROM ${process.env.DATABASE_NAME || process.env.MYSQL_DATABASE}`; // 替换为你要备份的表名
    const stream = connection.query(query);

    // 写入备份文件
    const writeStream = fs.createWriteStream(backupFile);
    stream.on('rows', (rows) => {
      // 处理结果集，并写入备份文件
      rows.forEach((row) => {
        // 将数据转换为字符串，并写入文件
        const rowString = Object.values(row).join(',');
        writeStream.write(rowString + '\n');
      });
    });
    stream.on('end', () => {
      console.log(`Database backup completed successfully! Backup file: ${backupFile}`);
    });

  } catch (err) {
    console.error('Error connecting to database:', err);
  } finally {
    // 关闭数据库连接
    if (connection) {
      connection.end();
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
    // 创建备份目录
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }
    // 连接数据库
    await pool.connect();

    // 获取当前时间作为备份文件名
    const timestamp = moment().format('YYYYMMDDHHmmss');
    const backupFile = path.join(backupDir, `backup-${timestamp}.sql`);

    // 首先获取所有表名
    const tablesQuery = `
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
    `;
    const { rows: tables } = await pool.query(tablesQuery);

    // 为每个表创建一个备份文件
    for (const table of tables) {
      // 跳过系统表
      if (table.table_name.startsWith('pg_') || table.table_name.startsWith('sql_')) {
        console.log(`Skipping system table: ${table.table_name}`);
        continue;
      } 
      const tableName = table.table_name;
      const tableBackupFile = path.join(backupDir, `${tableName}-${timestamp}.csv`);
      
      // 使用COPY命令备份单个表
      const copyQuery = `COPY ${tableName} TO STDOUT WITH (FORMAT CSV, HEADER)`;
      const writeStream = fs.createWriteStream(tableBackupFile);
      
      const copyStream = await pool.query(copyToStream(copyQuery));
      copyStream.pipe(writeStream);
      
      console.log(`Table ${tableName} backed up to ${tableBackupFile}`);
    }
    console.log('Database backup completed successfully!');
  } catch (err) {
    console.error('Error connecting to database:', err);
  } finally {
    // 关闭数据库连接
    if (pool) {
      pool.end();
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

    // 创建备份目录
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir);
    }
    // 连接数据库
    await pool.connect();

    // 获取当前时间作为备份文件名
    const timestamp = moment().format('YYYYMMDDHHmmss');
    const backupFile = path.join(backupDir, `backup-${timestamp}.sql`);

    // 直接备份指定的表
    const tableBackupFile = path.join(backupDir, `${tableName}-${timestamp}.csv`);
    
    // 验证表是否存在
    const tableExistsQuery = `
      SELECT EXISTS (
        SELECT 1 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = $1
      )`;
    const { rows: [{ exists }] } = await pool.query(tableExistsQuery, [tableName]);
    
    if (!exists) {
      throw new Error(`Table "${tableName}" does not exist`);
    }
    
    // 使用COPY命令备份指定表
    const copyQuery = `COPY ${tableName} TO STDOUT WITH (FORMAT CSV, HEADER)`;
    const writeStream = fs.createWriteStream(tableBackupFile);
    
    const copyStream = await pool.query(copyToStream(copyQuery));
    await new Promise((resolve, reject) => {
      copyStream.on('error', reject);
      writeStream.on('error', reject);
      writeStream.on('finish', resolve);
      copyStream.pipe(writeStream);
    });
    
    console.log(`Table ${tableName} backed up to ${tableBackupFile}`);
    console.log('Database backup completed successfully!');
  } catch (err) {
    console.error('Error connecting to database:', err);
  } finally {
    // 关闭数据库连接
    if (pool) {
      pool.end();
    }
  }
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
