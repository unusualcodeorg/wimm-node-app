import { Module } from '@nestjs/common';
import {
  Subscription,
  SubscriptionSchema,
} from './schemas/subscription.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { SubscriptionController } from './subscription.controller';
import { SubscriptionService } from './subscription.service';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: Subscription.name, schema: SubscriptionSchema },
    ]),
  ],
  controllers: [SubscriptionController],
  providers: [SubscriptionService],
  exports: [SubscriptionService],
})
export class SubscriptionModule {}
