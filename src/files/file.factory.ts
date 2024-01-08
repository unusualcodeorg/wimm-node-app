import { Injectable } from '@nestjs/common';
import { diskStorage } from 'multer';
import { extname, resolve } from 'path';
import { DiskConfig, DiskConfigName } from '../config/disk.config';
import { ConfigService } from '@nestjs/config';
import {
  MulterModuleOptions,
  MulterOptionsFactory,
} from '@nestjs/platform-express';

@Injectable()
export class FileDiskFactory implements MulterOptionsFactory {
  constructor(private readonly configService: ConfigService) {}

  createMulterOptions(): MulterModuleOptions {
    const diskConfig =
      this.configService.getOrThrow<DiskConfig>(DiskConfigName);

    const diskPath = resolve(__dirname, '../..', diskConfig.path);

    return {
      fileFilter: (_, file: Express.Multer.File, callback) => {
        const allowedExtensions = ['.jpg', '.jpeg', '.png'];
        const ext = extname(file.originalname).toLowerCase();
        if (allowedExtensions.includes(ext)) {
          return callback(null, true);
        }
        return callback(
          new Error('Only .jpg, .jpeg, and .png files are allowed'),
          false,
        );
      },
      storage: diskStorage({
        destination: diskPath,
        filename: (_, file, callback) => {
          const name = file.originalname.replace(/\s/g, '-');
          const uniqueSuffix =
            Date.now() + '-' + Math.round(Math.random() * 1e9);
          const ext = extname(file.originalname).toLowerCase();
          const fileName = `${name}_${uniqueSuffix}${ext}`;
          callback(null, fileName);
        },
      }),
    };
  }
}
