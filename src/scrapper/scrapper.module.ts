import { Module } from '@nestjs/common';
import { ScrapperService } from './scrapper.service';
import { ScrapperController } from './scrapper.controller';

@Module({
  providers: [ScrapperService],
  controllers: [ScrapperController],
})
export class ScrapperModule {}
