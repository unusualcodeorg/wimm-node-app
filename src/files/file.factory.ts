import { Injectable } from '@nestjs/common';
import { diskStorage } from 'multer';
import { extname } from 'path';
import {
  MulterModuleOptions,
  MulterOptionsFactory,
} from '@nestjs/platform-express';
import { FilesService } from './files.service';

@Injectable()
export class FileDiskFactory implements MulterOptionsFactory {
  constructor(private readonly filesService: FilesService) {}

  createMulterOptions(): MulterModuleOptions {
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
        destination: this.filesService.getDiskPath(),
        filename: (_, file, callback) => {
          const fileName = this.filesService.getFileName(file);
          callback(null, fileName);
        },
      }),
    };
  }
}
