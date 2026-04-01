import { Injectable, NotFoundException } from '@nestjs/common';

export interface Item {
  id: string;
  name: string;
  description: string;
  price: number;
  createdAt: Date;
}

/**
 * ItemsService
 *
 * In-memory store for Phase 1. In later phases we'll wire this to
 * a real database (Postgres), at which point the health/ready probe
 * will check DB connectivity here.
 *
 * This is why separation of concerns matters: swapping the storage
 * layer only changes this service, not the controller or infra config.
 */
@Injectable()
export class ItemsService {
  private items: Item[] = [
    {
      id: '1',
      name: 'Widget Alpha',
      description: 'A foundational widget for all DevOps needs',
      price: 29.99,
      createdAt: new Date('2024-01-01'),
    },
    {
      id: '2',
      name: 'Gadget Beta',
      description: 'Advanced gadget with container support',
      price: 49.99,
      createdAt: new Date('2024-01-15'),
    },
    {
      id: '3',
      name: 'Tool Gamma',
      description: 'Infrastructure automation at its finest',
      price: 99.99,
      createdAt: new Date('2024-02-01'),
    },
  ];

  findAll(): Item[] {
    return this.items;
  }

  findOne(id: string): Item {
    const item = this.items.find((i) => i.id === id);
    if (!item) {
      // NOTE: This 404 path is important for observability testing later.
      // You'll write a Prometheus counter that tracks 4xx responses
      // so you can alert on client-side errors spiking.
      throw new NotFoundException(`Item with id '${id}' not found`);
    }
    return item;
  }

  create(data: Omit<Item, 'id' | 'createdAt'>): Item {
    const newItem: Item = {
      id: String(this.items.length + 1),
      ...data,
      createdAt: new Date(),
    };
    this.items.push(newItem);
    return newItem;
  }
}
