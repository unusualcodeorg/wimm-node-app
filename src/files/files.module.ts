import { Module } from '@nestjs/common';
import { FilesController } from './files.controller';
import { ConfigModule } from '@nestjs/config';
import { MulterModule } from '@nestjs/platform-express';
import { FileDiskFactory } from './file.factory';

@Module({
  imports: [
    ConfigModule,
    MulterModule.registerAsync({
      imports: [ConfigModule],
      useClass: FileDiskFactory,
    }),
  ],
  controllers: [FilesController],
})
export class FilesModule {}
