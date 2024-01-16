import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { ApiKey } from './schemas/apikey.schema';

@Injectable()
export class CoreService {
  constructor(
    @InjectModel(ApiKey.name) private readonly apikeyModel: Model<ApiKey>,
  ) {}

  async findApiKey(key: string): Promise<ApiKey | null> {
    return this.apikeyModel.findOne({ key: key, status: true }).lean().exec();
  }

  async createApiKey(apikey: Omit<ApiKey, '_id' | 'status'>): Promise<ApiKey> {
    const created = await this.apikeyModel.create(apikey);
    return created.toObject();
  }

  async deleteApiKey(apikey: ApiKey) {
    return this.apikeyModel.findByIdAndDelete(apikey._id).lean().exec();
  }
}
