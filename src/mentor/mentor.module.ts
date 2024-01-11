import { Module } from '@nestjs/common';
import { Mentor, MentorSchema } from './schemas/mentor.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { MentorController } from './mentor.controller';
import { MentorService } from './mentor.service';
import { SubscriptionModule } from '../subscription/subscription.module';
import { MentorAdminController } from './mentor.admin.controller';
import { MentorsController } from './mentors.controller';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Mentor.name, schema: MentorSchema }]),
    SubscriptionModule,
  ],
  controllers: [MentorController, MentorAdminController, MentorsController],
  providers: [MentorService],
  exports: [MentorService],
})
export class MentorModule {}
