import { Module } from '@nestjs/common';
import { Mentor, MentorSchema } from './schemas/mentor.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { MentorController } from './mentor.controller';
import { MentorService } from './mentor.service';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Mentor.name, schema: MentorSchema }]),
  ],
  controllers: [MentorController],
  providers: [MentorService],
})
export class MentorModule {}
